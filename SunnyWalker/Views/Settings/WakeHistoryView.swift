// SunnyWalker — WakeHistoryView.swift  |  Day 22  |  P5 parent wake history

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct WakeHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\WakeRecord.wokeAt, order: .reverse)])
    private var records: [WakeRecord]

    @State private var showingExporter = false
    @State private var exportDocument = MarkdownDocument(text: "")

    var body: some View {
        NavigationStack {
            ZStack {
                SunnyColors.cloudWhite.ignoresSafeArea()
                if records.isEmpty {
                    emptyState
                } else {
                    recordList
                }
            }
            .navigationTitle("起床紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.sunnyGray)
                }
                if !records.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            exportDocument = MarkdownDocument(text: WakeHistoryMarkdown.build(from: records))
                            showingExporter = true
                        } label: {
                            Label("匯出 Markdown", systemImage: "square.and.arrow.up")
                        }
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.forestDeep)
                    }
                }
            }
            // 存成 .md 到「檔案」App，之後可從檔案分享到 LINE / 未來的 lode_iphone。
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: WakeHistoryMarkdown.markdownType,
                defaultFilename: WakeHistoryMarkdown.defaultFilename()
            ) { _ in }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🌙")
                .font(.system(size: 64))
            Text("還沒有起床紀錄")
                .font(SunnyFonts.title(22))
                .foregroundStyle(SunnyColors.nightIndigo)
            Text("小朋友每次成功起床後\n會在這裡留下記錄")
                .font(SunnyFonts.caption())
                .foregroundStyle(SunnyColors.sunnyGray)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Record list

    private var recordList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(records) { record in
                    WakeRecordCard(record: record)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - WakeRecordCard

private struct WakeRecordCard: View {
    let record: WakeRecord

    private var methodIcon: String {
        switch record.dismissMethod {
        case "voice":    return "mic.fill"
        case "button":   return "hand.tap.fill"
        case "fallback": return "hand.tap"
        case "timeout":  return "bell.slash.fill"   // 無人回應，背景自動停鈴
        default:         return "checkmark.circle"
        }
    }

    private var methodLabel: LocalizedStringKey {
        switch record.dismissMethod {
        case "voice":    return "method_voice"
        case "button":   return "method_button"
        case "fallback": return "method_fallback"
        case "timeout":  return "method_timeout"
        default:         return "method_default"
        }
    }

    var body: some View {
        WatercolorCard {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.alarmLabel)
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.nightIndigo)
                    Text(record.wokeAt.formatted(date: .abbreviated, time: .shortened))
                        .font(SunnyFonts.body(18))
                        .foregroundStyle(SunnyColors.nightIndigo)
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.caption)
                        Text(L("response_label %@", record.responseFormatted))
                            .font(SunnyFonts.caption(14))
                    }
                    .foregroundStyle(SunnyColors.sunnyGray)
                }
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: methodIcon)
                        .font(.system(size: 20))
                        .foregroundStyle(SunnyColors.leafFresh)
                    Text(methodLabel)
                        .font(SunnyFonts.caption(12))
                        .foregroundStyle(SunnyColors.sunnyGray)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - Markdown export

/// 一個極簡的 FileDocument，把 Markdown 字串寫成 .md 檔（給 .fileExporter 用）。
struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [WakeHistoryMarkdown.markdownType] }

    var text: String
    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// 把起床紀錄整理成 Markdown：頂部統計（回應率 / 準時相關）＋逐筆表格。
enum WakeHistoryMarkdown {
    /// "md" 在 iOS 對應 net.daringfireball.markdown（conforms to plainText）；取不到時退回純文字。
    static var markdownType: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }

    static func defaultFilename(now: Date = .now) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return "SunnyWalker_起床紀錄_\(f.string(from: now))"
    }

    /// dismissMethod 是否算「有回應」（小朋友主動關掉）。timeout = 無人回應。
    static func isResponded(_ method: String) -> Bool {
        method == "voice" || method == "button" || method == "fallback"
    }

    static func methodLabel(_ method: String) -> String {
        switch method {
        case "voice":    return "語音"
        case "button":   return "按鈕"
        case "fallback": return "輔助"
        case "timeout":  return "沒有回應（自動停止）"
        default:         return method
        }
    }

    static func build(from records: [WakeRecord], now: Date = .now) -> String {
        let total = records.count
        let responded = records.filter { isResponded($0.dismissMethod) }
        let noResponse = total - responded.count
        let responseRate = total > 0 ? Double(responded.count) / Double(total) * 100 : 0

        // 平均回應時間只看「有回應」的紀錄（timeout 的 responseSeconds ≈ 響鈴時長，會拉高平均）
        let avgResponse = responded.isEmpty
            ? 0
            : responded.map { $0.responseSeconds }.reduce(0, +) / responded.count

        // 各方式計數
        var methodCounts: [String: Int] = [:]
        for r in records { methodCounts[r.dismissMethod, default: 0] += 1 }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"

        var md = "# SunnyWalker 起床紀錄\n\n"
        md += "匯出時間：\(df.string(from: now))\n\n"
        md += "## 統計總覽\n\n"
        md += "- 總起床次數：**\(total)**\n"
        md += "- 有回應（小朋友主動關）：**\(responded.count)**\n"
        md += "- 沒有回應（自動停止）：**\(noResponse)**\n"
        md += String(format: "- 回應率：**%.0f%%**\n", responseRate)
        if !responded.isEmpty {
            md += "- 平均回應時間：**\(avgResponse) 秒**\n"
        }
        md += "\n### 各方式次數\n\n"
        for method in ["voice", "button", "fallback", "timeout"] where (methodCounts[method] ?? 0) > 0 {
            md += "- \(methodLabel(method))：\(methodCounts[method] ?? 0)\n"
        }

        md += "\n## 逐筆紀錄\n\n"
        md += "| 日期時間 | 鬧鐘 | 方式 | 回應秒數 |\n"
        md += "|---|---|---|---|\n"
        for r in records {
            let when = df.string(from: r.wokeAt)
            let label = r.alarmLabel.isEmpty ? "—" : r.alarmLabel
            let method = methodLabel(r.dismissMethod)
            let secs = isResponded(r.dismissMethod) ? "\(r.responseSeconds)" : "—"
            md += "| \(when) | \(label) | \(method) | \(secs) |\n"
        }

        return md
    }
}

#Preview {
    WakeHistoryView()
        .modelContainer(for: WakeRecord.self, inMemory: true)
}
