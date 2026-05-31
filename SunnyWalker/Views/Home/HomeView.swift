// SunnyWalker — HomeView.swift  |  Day 1  |  main screen (time + alarm list)

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Alarm.hour), SortDescriptor(\Alarm.minute)])
    private var alarms: [Alarm]

    @State private var currentTime = Date()
    @State private var showingAddAlarm = false

    // Ticks every second to keep the clock display live
    private let clockTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            background
            CloudBackground()
            VStack(spacing: 0) {
                clockHeader
                    .padding(.top, 56)
                    .padding(.bottom, 32)
                AlarmListView(alarms: alarms)
            }
            addButton
        }
        .ignoresSafeArea(edges: .top)
        .onReceive(clockTick) { currentTime = $0 }
    }

    // MARK: - Background

    private var background: some View {
        LinearGradient(
            colors: sceneColors,
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // Colours shift with the time of day — gives kids the "world is changing" feeling
    private var sceneColors: [Color] {
        let hour = Calendar.current.component(.hour, from: currentTime)
        switch hour {
        case 5..<7:   return [GhibliColors.lanternOrange, GhibliColors.wheatGold]
        case 7..<11:  return [GhibliColors.skyBlue, GhibliColors.cloudWhite]
        case 11..<15: return [GhibliColors.noonSky, GhibliColors.cloudWhite]
        case 15..<19: return [GhibliColors.lanternOrange.opacity(0.9), GhibliColors.wheatGold.opacity(0.7)]
        default:      return [GhibliColors.nightIndigo, GhibliColors.nightDeep]
        }
    }

    private var clockTextColor: Color {
        let hour = Calendar.current.component(.hour, from: currentTime)
        return hour >= 19 || hour < 5 ? GhibliColors.starGold : GhibliColors.nightIndigo
    }

    // MARK: - Clock header

    private var clockHeader: some View {
        VStack(spacing: 6) {
            Text(currentTime, format: .dateTime.hour().minute())
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .foregroundStyle(clockTextColor)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: currentTime)

            Text(currentTime, format: .dateTime.weekday(.wide).month().day())
                .font(.title3.weight(.medium))
                .foregroundStyle(clockTextColor.opacity(0.7))
        }
    }

    // MARK: - Add alarm FAB

    private var addButton: some View {
        Button {
            showingAddAlarm = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(GhibliColors.lanternOrange)
                .clipShape(Circle())
                .shadow(color: GhibliColors.lanternOrange.opacity(0.45), radius: 10, y: 5)
        }
        .padding(24)
        // Alarm editor sheet will be wired on Day 4+
        .sheet(isPresented: $showingAddAlarm) {
            AddAlarmPlaceholder()
        }
    }
}

// MARK: - Day 1 placeholder sheet

private struct AddAlarmPlaceholder: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("🚧")
                    .font(.system(size: 56))
                Text("新增鬧鐘")
                    .font(.title2.bold())
                    .foregroundStyle(GhibliColors.nightIndigo)
                Text("設定畫面將在 Day 4 完成")
                    .font(.subheadline)
                    .foregroundStyle(GhibliColors.totoroGray)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: Alarm.self, inMemory: true)
}
