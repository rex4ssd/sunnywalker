// SunnyWalker — AlarmListView.swift  |  Day 1  |  alarm card list (pure UI)

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
                .padding(.bottom, 100)  // room for + FAB
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🌿")
                .font(.system(size: 64))
            Text("還沒有鬧鐘")
                .font(.title2.weight(.semibold))
                .foregroundStyle(GhibliColors.nightIndigo)
            Text("點右下角的 + 來新增第一個吧！")
                .font(.subheadline)
                .foregroundStyle(GhibliColors.totoroGray)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - AlarmCard

private struct AlarmCard: View {
    @Bindable var alarm: Alarm

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(alarm.timeString)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        alarm.isEnabled ? GhibliColors.nightIndigo : GhibliColors.totoroGray
                    )
                HStack(spacing: 4) {
                    Text(alarm.label)
                        .font(.subheadline)
                        .foregroundStyle(GhibliColors.totoroGray)
                    if !alarm.weekdays.isEmpty {
                        Text("·")
                            .foregroundStyle(GhibliColors.totoroGray.opacity(0.5))
                        Text(alarm.weekdaySymbols.joined(separator: " "))
                            .font(.caption)
                            .foregroundStyle(GhibliColors.totoroGray.opacity(0.8))
                    }
                }
            }
            Spacer()
            Toggle("", isOn: $alarm.isEnabled)
                .tint(GhibliColors.leafFresh)
                .labelsHidden()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(GhibliColors.cloudWhite)
                .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
        )
        .opacity(alarm.isEnabled ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.2), value: alarm.isEnabled)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Alarm.self, configurations: config)
    let sample = Alarm(label: "上學囉", hour: 7, minute: 30)
    let sample2 = Alarm(label: "午睡起床", hour: 13, minute: 0)
    sample2.isEnabled = false
    return AlarmListView(alarms: [sample, sample2])
        .modelContainer(container)
        .background(GhibliColors.skyBlue)
}
