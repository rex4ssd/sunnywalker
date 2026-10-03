// SunnyWalkerTests — GroupOrderTests.swift

import XCTest
@testable import SunnyWalker

/// 群組長按拖曳換順序（Rex 2026-10-03）：順序只是一個排列，群組身分（groupIndex）不動。
final class GroupOrderTests: XCTestCase {

    func testSanitizeFillsMissingAndDropsJunk() {
        XCTAssertEqual(AppSettings.sanitizedGroupOrder([]), [0, 1, 2, 3, 4])
        XCTAssertEqual(AppSettings.sanitizedGroupOrder([2, 0]), [2, 0, 1, 3, 4])
        XCTAssertEqual(AppSettings.sanitizedGroupOrder([9, 2, 2, -1, 4]), [2, 4, 0, 1, 3])
    }

    func testDefaultOrderMatchesOldBehaviour() {
        // 沒排過：前 count 個＝0..<count，跟以前「索引 < count」完全一樣。
        for n in 1...AppSettings.maxGroups {
            XCTAssertEqual(AppSettings.visibleGroups(order: [], count: n, enabled: true), Array(0..<n))
        }
        XCTAssertEqual(AppSettings.visibleGroups(order: [2, 1, 0], count: 3, enabled: false), [0])
    }

    func testVisibleFollowsOrderAndCountTrimsBottom() {
        let order = [2, 0, 1, 3, 4]
        XCTAssertEqual(AppSettings.visibleGroups(order: order, count: 3, enabled: true), [2, 0, 1])
        // 按「－」收掉的是排在最下面那組（B），不是字母最大的 C。
        XCTAssertEqual(AppSettings.visibleGroups(order: order, count: 2, enabled: true), [2, 0])
    }

    func testFiringGateUsesOrder() {
        let d = UserDefaults.standard
        let keys = ["groupEnabled", "groupCount", "groupOrder", "groupActiveStates"]
        let saved = keys.map { d.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { v == nil ? d.removeObject(forKey: k) : d.set(v, forKey: k) } }

        d.set(true, forKey: "groupEnabled")
        d.set(2, forKey: "groupCount")
        d.set([2, 0, 1, 3, 4], forKey: "groupOrder")
        d.removeObject(forKey: "groupActiveStates")
        XCTAssertTrue(AppSettings.groupAllowsFiring(2))
        XCTAssertTrue(AppSettings.groupAllowsFiring(0))
        XCTAssertFalse(AppSettings.groupAllowsFiring(1))

        d.removeObject(forKey: "groupOrder")   // 舊使用者：沒有 groupOrder
        XCTAssertTrue(AppSettings.groupAllowsFiring(1))
        XCTAssertFalse(AppSettings.groupAllowsFiring(2))
    }

    @MainActor
    func testMoveKeepsHiddenGroupsAndVisibleSet() {
        let s = AppSettings.shared
        let saved = (s.groupEnabled, s.groupCount, s.groupOrder)
        defer { s.groupEnabled = saved.0; s.groupCount = saved.1; s.groupOrder = saved.2 }

        s.groupEnabled = true
        s.groupCount = 3
        s.groupOrder = [0, 1, 2, 3, 4]
        s.moveGroups(fromOffsets: IndexSet(integer: 2), toOffset: 0)   // C 拖到最上面
        XCTAssertEqual(s.groupOrder, [2, 0, 1, 3, 4])
        XCTAssertEqual(s.visibleGroups, [2, 0, 1])
        XCTAssertEqual(UserDefaults.standard.array(forKey: "groupOrder") as? [Int], [2, 0, 1, 3, 4])
    }
}
