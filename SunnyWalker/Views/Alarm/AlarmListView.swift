// SunnyWalker — AlarmListView.swift  |  Day 2  |  WatercolorCard alarm list

import SwiftUI
import SwiftData

struct AlarmListView: View {
    let alarms: [Alarm]

    var body: some View {
        if alarms.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(alarms) { alarm in
                        AlarmCard(alarm: alarm)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
    }

    // Empty state: message + ghost sample cards so the layout reads naturally
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("🌿")
                        .font(.system(size: 56))
                    Text("還沒有鬧鐘")
                        .font(GhibliFonts.title(22))
                        .foregroundStyle(GhibliColors.nightIndigo)
                    Text("點右下角的 + 來新增第一個吧！")
                        .font(GhibliFonts.caption())
                        .foregroundStyle(GhibliColors.totoroGray)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)

                LazyVStack(spacing: 12) {
                    ForEach(Self.sampleAlarms) { alarm in
                        SampleAlarmCard(alarm: alarm)
                    }
                }
                .padding(.horizontal, 20)
                .opacity(0.4)
            }
            .padding(.bottom, 100)
        }
    }

    // Display-only sample alarms — shown when list is empty
    private static var sampleAlarms: [Alarm] {
        let a = Alarm(label: "上學囉", hour: 7, minute: 30)
        let b = Alarm(label: "午睡起床", hour: 13, minute: 0)
        b.isEnabled = false
        return [a, b]
    }
}

// MARK: - AlarmCard (interactive, wrapped in WatercolorCard)

private struct AlarmCard: View {
    @Bindable var alarm: Alarm
    @State private var showingRecording = false

    var body: some View {
        WatercolorCard {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(alarm.timeString)
                        .font(GhibliFonts.clock(40))
                        .foregroundStyle(
                            alarm.isEnabled ? GhibliColors.nightIndigo : GhibliColors.totoroGray
                        )
                    HStack(spacing: 4) {
                        Text(alarm.label)
                            .font(GhibliFonts.caption())
                            .foregroundStyle(GhibliColors.totoroGray)
                        if !alarm.weekdays.isEmpty {
                            Text("·")
                                .foregroundStyle(GhibliColors.totoroGray.opacity(0.5))
                            Text(alarm.weekdaySymbols.joined(separator: " "))
                                .font(GhibliFonts.caption(14))
                                .foregroundStyle(GhibliColors.totoroGray.opacity(0.8))
                        }
                    }
                }
                Spacer()
                Button {
                    showingRecording = true
                } label: {
                    Image(systemName: alarm.recordingName.isEmpty ? "mic" : "mic.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(alarm.recordingName.isEmpty
                            ? GhibliColors.totoroGray.opacity(0.6)
                            : GhibliColors.leafFresh)
                }
                .padding(.trailing, 14)
                .accessibilityLabel(alarm.recordingName.isEmpty ? "錄製起床音" : "已錄製起床音")
                Toggle("", isOn: $alarm.isEnabled)
                    .tint(GhibliColors.leafFresh)
                    .labelsHidden()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .opacity(alarm.isEnabled ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.2), value: alarm.isEnabled)
        .onChange(of: alarm.isEnabled) { _, _ in
            Task { try? await AlarmScheduler.shared.syncWithModel(alarm: alarm) }
        }
        .sheet(isPresented: $showingRecording) {
            RecordingView(alarm: alarm)
        }
    }
}

// MARK: - SampleAlarmCard (display-only, no @Bindable, toggle disabled)

private struct SampleAlarmCard: View {
    let alarm: Alarm

    var body: some View {
        WatercolorCard {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(alarm.timeString)
                        .font(GhibliFonts.clock(40))
                        .foregroundStyle(GhibliColors.nightIndigo)
                    Text(alarm.label)
                        .font(GhibliFonts.caption())
                        .foregroundStyle(GhibliColors.totoroGray)
                }
                Spacer()
                Toggle("", isOn: .constant(alarm.isEnabled))
                    .tint(GhibliColors.leafFresh)
                    .labelsHidden()
                    .disabled(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }
}

#Preview("With alarms") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Alarm.self, configurations: config)
    let sample = Alarm(label: "上學囉", hour: 7, minute: 30)
    let sample2 = Alarm(label: "午睡起床", hour: 13, minute: 0)
    sample2.isEnabled = false
    return AlarmListView(alarms: [sample, sample2])
        .modelContainer(container)
        .background(GhibliColors.skyBlue)
}

#Preview("Empty state") {
    AlarmListView(alarms: [])
        .modelContainer(for: Alarm.self, inMemory: true)
        .background(GhibliColors.skyBlue)
}
