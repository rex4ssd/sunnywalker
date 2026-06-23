// SunnyWalker — TodoHistoryView.swift  |  待辦紀錄：兒童有沒有去聽當天的提醒
//
// 列出每一筆 TodoPlayRecord（兒童在主頁點/長按待辦圖示播放提醒語音的紀錄），最新在上。
// 家長用來確認孩子有沒有看到當天的注意事項。

import SwiftUI
import SwiftData

struct TodoHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoPlayRecord.playedAt, order: .reverse) private var records: [TodoPlayRecord]

    var body: some View {
        NavigationStack {
            ZStack {
                SunnyColors.cloudWhite.ignoresSafeArea()
                if records.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(records) { record in
                            row(record)
                                .listRowBackground(Color.white.opacity(0.75))
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("todo_history_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .font(SunnyFonts.caption())
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "balloon.2")
                .font(.system(size: 44))
                .foregroundStyle(SunnyColors.sunnyGray.opacity(0.5))
            Text("todo_history_empty")
                .font(SunnyFonts.caption())
                .foregroundStyle(SunnyColors.sunnyGray)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func row(_ record: TodoPlayRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(SunnyColors.leafFresh)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: record.todoLabel.isEmpty ? L("待辦提醒") : record.todoLabel)
                    .font(SunnyFonts.title(16))
                    .foregroundStyle(SunnyColors.nightIndigo)
                    .lineLimit(1)
                Text(verbatim: L("todo_history_scheduled %@",
                                 String(format: "%02d:%02d", record.scheduledHour, record.scheduledMinute)))
                    .font(SunnyFonts.caption(12))
                    .foregroundStyle(SunnyColors.sunnyGray)
            }
            Spacer()
            Text(verbatim: Self.playedFormatter.string(from: record.playedAt))
                .font(SunnyFonts.caption(12))
                .foregroundStyle(SunnyColors.forestDeep)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(records[index]) }
        try? modelContext.save()
    }

    private static let playedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = SunnyLocalization.locale
        f.dateFormat = "M/d HH:mm"
        return f
    }()
}
