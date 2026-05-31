// SunnyWalker — AlarmIOView.swift  |  鬧鐘設定的 Markdown 匯入 / 匯出畫面

import SwiftUI
import SwiftData

struct AlarmIOView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Alarm.hour), SortDescriptor(\Alarm.minute)])
    private var alarms: [Alarm]

    @State private var importText = ""
    @State private var replaceOnImport = false
    @State private var resultMessage: String?

    private var exportText: String { MarkdownAlarmIO.export(alarms) }

    var body: some View {
        NavigationStack {
            Form {
                Section("匯出") {
                    Text(exportText)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    ShareLink("分享 / 匯出 Markdown", item: exportText)
                }

                Section("匯入") {
                    TextEditor(text: $importText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 120)
                    Button("從剪貼簿貼上") {
                        importText = UIPasteboard.general.string ?? ""
                    }
                    Toggle("覆蓋現有鬧鐘", isOn: $replaceOnImport)
                    Button("匯入") { runImport() }
                        .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let msg = resultMessage {
                    Section { Text(msg).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("匯入 / 匯出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func runImport() {
        let parsed = MarkdownAlarmIO.parse(importText)

        if replaceOnImport {
            for old in alarms {
                AlarmScheduler.shared.cancel(old.id)
                modelContext.delete(old)
            }
        }

        for p in parsed {
            let alarm = Alarm(label: p.label.isEmpty ? "鬧鐘" : p.label,
                              hour: p.hour, minute: p.minute)
            alarm.weekdays = p.weekdays
            alarm.isEnabled = p.isEnabled
            modelContext.insert(alarm)
            if p.isEnabled {
                Task { try? await AlarmScheduler.shared.schedule(alarm: alarm) }
            }
        }

        resultMessage = "成功匯入 \(parsed.count) 筆鬧鐘"
        importText = ""
    }
}

#Preview {
    AlarmIOView()
        .modelContainer(for: Alarm.self, inMemory: true)
}
