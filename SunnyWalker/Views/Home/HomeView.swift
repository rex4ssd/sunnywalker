// SunnyWalker — HomeView.swift  |  Day 10  |  iPad landscape guard

import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: [SortDescriptor(\Alarm.hour), SortDescriptor(\Alarm.minute)])
    private var alarms: [Alarm]

    @State private var currentTime = Date()

    // "+" (add alarm) gate states
    @State private var showingParentalGate = false
    @State private var gateDidSucceed = false
    @State private var showingAddAlarm = false

    // Notification-driven / long-press alarm ring
    @State private var firingAlarm: Alarm?

    // IO button gate states
    @State private var showingParentalGateForIO = false
    @State private var gateDidSucceedIO = false
    @State private var showingIO = false

    private let clockTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var scene: DaytimeScene {
        DaytimeScene.current(hour: Calendar.current.component(.hour, from: currentTime))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            background
            CloudBackground()
            if sizeClass == .regular {
                // iPad: GeometryReader distinguishes landscape (width > height) from portrait.
                // The prior sizeClass == .regular && vSizeClass == .compact condition was dead code
                // because iPad landscape gives verticalSizeClass = .regular, not .compact.
                GeometryReader { geo in
                    if geo.size.width > geo.size.height {
                        // iPad landscape: compact two-column with smaller clock to avoid clipping
                        HStack(spacing: 0) {
                            VStack(spacing: 8) {
                                clockHeader(fontSize: 52)
                                    .padding(.top, 32)
                                    .padding(.bottom, 8)
                                TotoroAvatar()
                                    .scaleEffect(0.75)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            AlarmListView(alarms: alarms)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        // iPad portrait: side-by-side clock/avatar | alarm list
                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                clockHeader()
                                    .padding(.top, 56)
                                    .padding(.bottom, 16)
                                TotoroAvatar()
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            AlarmListView(alarms: alarms)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                // iPhone: stacked layout
                VStack(spacing: 0) {
                    clockHeader()
                        .padding(.top, 56)
                        .padding(.bottom, 12)
                    TotoroAvatar()
                        .padding(.bottom, 8)
                    AlarmListView(alarms: alarms)
                }
            }
            addButton
        }
        .ignoresSafeArea(edges: .top)
        .onAppear { checkPendingAlarm() }
        .onReceive(clockTick) { currentTime = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .alarmFired)) { note in
            guard let uuidString = note.object as? String,
                  let uuid = UUID(uuidString: uuidString),
                  let alarm = alarms.first(where: { $0.id == uuid }) else { return }
            firingAlarm = alarm
        }
        .fullScreenCover(item: $firingAlarm) { alarm in
            AlarmRingView(alarm: alarm)
        }
    }

    // Handles the killed-state case: AppDelegate stored the alarm ID before HomeView was ready.
    // Accepts an injected delegate to allow unit testing without UIApplicationMain.
    func checkPendingAlarm(delegate: AppDelegate? = UIApplication.shared.delegate as? AppDelegate) {
        guard let delegate, let id = delegate.pendingAlarmID else { return }
        delegate.pendingAlarmID = nil
        guard let uuid = UUID(uuidString: id),
              let alarm = alarms.first(where: { $0.id == uuid }) else { return }
        firingAlarm = alarm
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

    private func clockHeader(fontSize: CGFloat = 76) -> some View {
        VStack(spacing: 6) {
            Text(currentTime, format: .dateTime.hour().minute())
                .font(GhibliFonts.clock(fontSize))
                .foregroundStyle(scene.clockTextColor)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: currentTime)

            Text(currentTime, format: .dateTime.weekday(.wide).month().day())
                .font(GhibliFonts.subtitle())
                .foregroundStyle(scene.clockTextColor.opacity(0.7))
        }
    }

    // MARK: - FAB buttons (add alarm + IO)

    private var addButton: some View {
        VStack(spacing: 16) {
            // IO / export button — gated behind parental gate
            Button {
                showingParentalGateForIO = true
            } label: {
                Image(systemName: "square.and.arrow.up.on.square")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(GhibliColors.leafFresh)
                    .clipShape(Circle())
                    .shadow(color: GhibliColors.leafFresh.opacity(0.45), radius: 8, y: 4)
            }
            // Add alarm button — gated behind parental gate
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
        // Parental gate for "+" → AlarmEditorView
        .sheet(isPresented: $showingParentalGate, onDismiss: {
            if gateDidSucceed {
                gateDidSucceed = false
                showingAddAlarm = true
            }
        }) {
            ParentalGateView(onSuccess: { gateDidSucceed = true })
        }
        .sheet(isPresented: $showingAddAlarm) {
            AlarmEditorView()
        }
        // Parental gate for IO → AlarmIOView
        .sheet(isPresented: $showingParentalGateForIO, onDismiss: {
            if gateDidSucceedIO {
                gateDidSucceedIO = false
                showingIO = true
            }
        }) {
            ParentalGateView(onSuccess: { gateDidSucceedIO = true })
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
