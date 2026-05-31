// SunnyWalker — HomeView.swift  |  Day 2  |  main screen (time + Totoro + alarm list)

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Alarm.hour), SortDescriptor(\Alarm.minute)])
    private var alarms: [Alarm]

    @State private var currentTime = Date()
    @State private var showingParentalGate = false
    @State private var gateDidSucceed = false
    @State private var showingAddAlarm = false
    @State private var showingAlarmRing = false
    @State private var showingIO = false

    private let clockTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var scene: DaytimeScene {
        DaytimeScene.current(hour: Calendar.current.component(.hour, from: currentTime))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            background
            CloudBackground()
            VStack(spacing: 0) {
                clockHeader
                    .padding(.top, 56)
                    .padding(.bottom, 12)
                TotoroAvatar()
                    .padding(.bottom, 8)
                    .onLongPressGesture { showingAlarmRing = true }
                AlarmListView(alarms: alarms)
            }
            addButton
        }
        .ignoresSafeArea(edges: .top)
        .onReceive(clockTick) { currentTime = $0 }
        .fullScreenCover(isPresented: $showingAlarmRing) { AlarmRingView(alarm: alarms.first) }
    }

    // MARK: - Background

    private var background: some View {
        LinearGradient(
            colors: scene.gradientColors,
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Clock header

    private var clockHeader: some View {
        VStack(spacing: 6) {
            Text(currentTime, format: .dateTime.hour().minute())
                .font(GhibliFonts.clock())
                .foregroundStyle(scene.clockTextColor)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: currentTime)

            Text(currentTime, format: .dateTime.weekday(.wide).month().day())
                .font(GhibliFonts.subtitle())
                .foregroundStyle(scene.clockTextColor.opacity(0.7))
        }
    }

    // MARK: - Add alarm FAB

    private var addButton: some View {
        VStack(spacing: 16) {
            Button {
                showingIO = true
            } label: {
                Image(systemName: "square.and.arrow.up.on.square")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(GhibliColors.leafFresh)
                    .clipShape(Circle())
                    .shadow(color: GhibliColors.leafFresh.opacity(0.45), radius: 8, y: 4)
            }
            Button {
                showingParentalGate = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(GhibliColors.lanternOrange)
                    .clipShape(Circle())
                    .shadow(color: GhibliColors.lanternOrange.opacity(0.45), radius: 10, y: 5)
            }
        }
        .padding(24)
        .sheet(isPresented: $showingParentalGate, onDismiss: {
            if gateDidSucceed {
                gateDidSucceed = false
                showingAddAlarm = true
            }
        }) {
            ParentalGateView(onSuccess: {
                gateDidSucceed = true
            })
        }
        .sheet(isPresented: $showingAddAlarm) {
            AlarmEditorView()
        }
        .sheet(isPresented: $showingIO) {
            AlarmIOView()
        }
    }
}


#Preview {
    HomeView()
        .modelContainer(for: Alarm.self, inMemory: true)
}
