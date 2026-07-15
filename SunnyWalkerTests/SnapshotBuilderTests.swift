// SunnyWalker — SnapshotBuilderTests.swift  |  統一學習快照（kids.snapshot.v1）聚合測試
//
// in-memory ModelContainer 餵假 WakeRecord → SnapshotBuilder.build（now / calendar / isZh 全注入，
// 不碰 UserDefaults / Bundle / 真時鐘），驗證 progress / favorites / weaknesses 映射口徑。

import XCTest
import SwiftData
import KidsDataCore
@testable import SunnyWalker

final class SnapshotBuilderTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    /// 固定時區與「現在」，讓「每日」切齊、測試決定性。
    private let calendar: Calendar = {
        var fixed = Calendar(identifier: .gregorian)
        fixed.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return fixed
    }()
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 9))!
    }

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: WakeRecord.self, configurations: config)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    /// 插入一筆假紀錄：daysAgo 天前 07:00 響鈴、responseSeconds 秒後起床。
    @discardableResult
    private func insertRecord(daysAgo: Int,
                              label: String = "上學鬧鐘",
                              method: String = "voice",
                              responseSeconds: Int = 30) -> WakeRecord {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        let firedAt = calendar.date(byAdding: .hour, value: 7, to: day)!
        let record = WakeRecord(alarmID: UUID(), alarmLabel: label, firedAt: firedAt,
                                wokeAt: firedAt.addingTimeInterval(TimeInterval(responseSeconds)),
                                dismissMethod: method)
        context.insert(record)
        return record
    }

    private func fetchAll() throws -> [WakeRecord] {
        try context.fetch(FetchDescriptor<WakeRecord>())
    }

    private func build(isZh: Bool = true) throws -> KidsLearningSnapshot {
        SnapshotBuilder.build(records: try fetchAll(),
                              now: now,
                              calendar: calendar,
                              appVersion: "9.9.9",
                              profileId: "kid-test01",
                              timezone: "Asia/Taipei",
                              isZh: isZh)
    }

    // MARK: - 快照 envelope

    func testEnvelopeFields() throws {
        insertRecord(daysAgo: 0)
        let snapshot = try build()
        XCTAssertEqual(snapshot.app, .sunnywalker)
        XCTAssertEqual(snapshot.appVersion, "9.9.9")
        XCTAssertEqual(snapshot.profileId, "kid-test01")
        XCTAssertEqual(snapshot.timezone, "Asia/Taipei")
        XCTAssertEqual(snapshot.schemaVersion, KidsSnapshotSchema.version)
        XCTAssertTrue(snapshot.avoidances.isEmpty, "avoidances 規格留空")
    }

    // MARK: - progress

    func testProgressSuccessDaysStreakAndAverage() throws {
        // 連續三天成功（今天、昨天、前天），回應 10 / 20 / 30 秒 → 平均 20。
        insertRecord(daysAgo: 0, responseSeconds: 10)
        insertRecord(daysAgo: 1, responseSeconds: 20)
        insertRecord(daysAgo: 2, responseSeconds: 30)
        // timeout 不算成功、也不進平均。
        insertRecord(daysAgo: 4, method: "timeout", responseSeconds: 600)

        let snapshot = try build()
        let byMetric = Dictionary(uniqueKeysWithValues: snapshot.progress.map { ($0.metric, $0) })

        XCTAssertEqual(byMetric["success_days"]?.value, 3)
        XCTAssertEqual(byMetric["streak_days"]?.value, 3)
        XCTAssertEqual(byMetric["avg_response_seconds"]?.value, 20)
        XCTAssertEqual(byMetric["avg_response_seconds"]?.display, "20 秒")
    }

    func testStreakSkipsTodayWithoutBreaking() throws {
        // 今天還沒成功起床：連續數改從昨天起算，不斷鏈。
        insertRecord(daysAgo: 1)
        insertRecord(daysAgo: 2)
        let snapshot = try build()
        XCTAssertEqual(snapshot.progress.first { $0.metric == "streak_days" }?.value, 2)
    }

    func testStreakBrokenByGap() throws {
        insertRecord(daysAgo: 0)
        insertRecord(daysAgo: 2)   // 昨天沒成功 → 鏈斷在今天
        let snapshot = try build()
        XCTAssertEqual(snapshot.progress.first { $0.metric == "streak_days" }?.value, 1)
    }

    func testWindowExcludesRecordsOlderThan30Days() throws {
        insertRecord(daysAgo: 0)
        insertRecord(daysAgo: 40)   // 視窗外，不得計入
        let snapshot = try build()
        XCTAssertEqual(snapshot.progress.first { $0.metric == "success_days" }?.value, 1)
        XCTAssertEqual(snapshot.favorites.first?.count, 1)
    }

    // MARK: - favorites

    func testFavoritesRankedByTriggerCount() throws {
        insertRecord(daysAgo: 0, label: "上學鬧鐘")
        insertRecord(daysAgo: 1, label: "上學鬧鐘")
        insertRecord(daysAgo: 1, label: "午睡", method: "timeout", responseSeconds: 600)

        let snapshot = try build()
        XCTAssertEqual(snapshot.favorites.map(\.title), ["上學鬧鐘", "午睡"])
        XCTAssertEqual(snapshot.favorites.map(\.count), [2, 1])
        XCTAssertEqual(snapshot.favorites[0].share ?? 0, 2.0 / 3.0, accuracy: 0.0001)
    }

    // MARK: - weaknesses

    func testFallbackRatioWeakness() throws {
        // 4 筆中 1 筆 fallback → mistakeCount 1、opportunities 4、successRate 0.75。
        insertRecord(daysAgo: 0)
        insertRecord(daysAgo: 1)
        insertRecord(daysAgo: 2)
        insertRecord(daysAgo: 3, method: "fallback")

        let snapshot = try build()
        let weakness = try XCTUnwrap(snapshot.weaknesses.first { $0.skill == "fallback_dismiss" })
        XCTAssertEqual(weakness.title, "需要大人幫忙關")
        XCTAssertEqual(weakness.mistakeCount, 1)
        XCTAssertEqual(weakness.opportunities, 4)
        XCTAssertEqual(try XCTUnwrap(weakness.successRate), 0.75, accuracy: 0.0001)
    }

    func testNoFallbackMeansNoFallbackWeakness() throws {
        insertRecord(daysAgo: 0)
        let snapshot = try build()
        XCTAssertFalse(snapshot.weaknesses.contains { $0.skill == "fallback_dismiss" })
    }

    func testSlowResponseAlarmWeakness() throws {
        // 「起床號」三筆有回應且平均 140 秒（≥ 120、樣本數 ≥ 3）→ 列入 slow_response。
        insertRecord(daysAgo: 0, label: "起床號", responseSeconds: 130)
        insertRecord(daysAgo: 1, label: "起床號", responseSeconds: 150)
        insertRecord(daysAgo: 2, label: "起床號", responseSeconds: 140)
        // 「快手」樣本夠但平均快 → 不列入。
        insertRecord(daysAgo: 0, label: "快手", responseSeconds: 5)
        insertRecord(daysAgo: 1, label: "快手", responseSeconds: 5)
        insertRecord(daysAgo: 2, label: "快手", responseSeconds: 5)

        let snapshot = try build()
        let slows = snapshot.weaknesses.filter { $0.skill == "slow_response" }
        XCTAssertEqual(slows.count, 1)
        let weakness = try XCTUnwrap(slows.first)
        XCTAssertEqual(weakness.title, "起床特別慢：起床號")
        XCTAssertEqual(weakness.mistakeCount, 3)      // 三筆都 ≥ 120 秒
        XCTAssertEqual(weakness.opportunities, 3)
        XCTAssertEqual(try XCTUnwrap(weakness.successRate), 0, accuracy: 0.0001)
    }

    func testSlowResponseNeedsMinimumSamples() throws {
        // 只有兩筆（< slowResponseMinSamples）→ 即使很慢也不列入。
        insertRecord(daysAgo: 0, label: "起床號", responseSeconds: 300)
        insertRecord(daysAgo: 1, label: "起床號", responseSeconds: 300)
        let snapshot = try build()
        XCTAssertFalse(snapshot.weaknesses.contains { $0.skill == "slow_response" })
    }

    // MARK: - 英文文字口徑

    func testEnglishTitles() throws {
        insertRecord(daysAgo: 0, method: "fallback")
        let snapshot = try build(isZh: false)
        XCTAssertEqual(snapshot.progress.first { $0.metric == "success_days" }?.title,
                       "Successful wake days (last 30 days)")
        XCTAssertEqual(snapshot.weaknesses.first?.title, "Needed a grown-up to dismiss")
    }

    // MARK: - 與共用件的整條路（render → extract 無損回讀）

    func testRenderRoundTripThroughSharedMarkdown() throws {
        insertRecord(daysAgo: 0)
        insertRecord(daysAgo: 1, method: "fallback")
        let snapshot = try build()

        let markdown = KidsSnapshotMarkdown.render(snapshot, strings: .zhHant, appDisplayName: "SunnyWalker")
        XCTAssertTrue(markdown.contains("kids-schema: kids.snapshot.v1"))
        XCTAssertTrue(markdown.contains("# SunnyWalker 學習報告"))

        let back = try XCTUnwrap(KidsSnapshotMarkdown.extractSnapshot(fromMarkdown: markdown))
        XCTAssertEqual(back, snapshot)

        XCTAssertEqual(KidsSnapshotMarkdown.suggestedFileName(for: snapshot),
                       "sunnywalker_snapshot_20260713.md")
    }
}
