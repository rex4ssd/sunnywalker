// SunnyWalker — SettingsView.swift  |  Day 30  |  Unified settings sheet

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var localization = LocalizationManager.shared

    // Parental gate for History
    @State private var showingGateForHistory = false
    @State private var gateHistoryOK = false
    @State private var showingHistory = false

    // Parental gate for IO
    @State private var showingGateForIO = false
    @State private var gateIOOK = false
    @State private var showingIO = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Time format
                Section(header: Text("time_format_section")) {
                    HStack {
                        Label("12h_label", systemImage: "clock")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !settings.use24HourClock },
                            set: { settings.use24HourClock = !$0 }
                        ))
                        .tint(SunnyColors.leafFresh)
                        .labelsHidden()
                    }
                    HStack {
                        Label("24h_label", systemImage: "clock.fill")
                        Spacer()
                        Toggle("", isOn: $settings.use24HourClock)
                            .tint(SunnyColors.leafFresh)
                            .labelsHidden()
                    }
                }

                // MARK: - Language
                Section(header: Text("language_section")) {
                    Picker(selection: $localization.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayKey).tag(lang)
                        }
                    } label: {
                        Label("language_setting", systemImage: "globe")
                    }
                    .pickerStyle(.navigationLink)
                }

                // MARK: - Wake recording gap
                Section(
                    header: Text("recording_gap_section"),
                    footer: Text("recording_gap_footer")
                ) {
                    Stepper(value: $settings.recordingGapSeconds, in: 0...5) {
                        HStack {
                            Label("recording_gap_label", systemImage: "waveform")
                            Spacer()
                            Text("\(settings.recordingGapSeconds) s")
                                .foregroundStyle(SunnyColors.sunnyGray)
                                .monospacedDigit()
                        }
                    }
                }

                // MARK: - Parental section
                Section(header: Text("parental_section")) {
                    // Wake History
                    Button {
                        showingGateForHistory = true
                    } label: {
                        Label("起床紀錄", systemImage: "chart.bar.fill")
                            .foregroundStyle(SunnyColors.forestDeep)
                    }

                    // Import / Export
                    Button {
                        showingGateForIO = true
                    } label: {
                        Label("匯入 / 匯出", systemImage: "square.and.arrow.up.on.square")
                            .foregroundStyle(SunnyColors.leafFresh)
                    }
                }
            }
            .navigationTitle(Text("settings_label"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .font(SunnyFonts.caption())
                }
            }
        }
        // Parental gate → WakeHistoryView
        .sheet(isPresented: $showingGateForHistory, onDismiss: {
            if gateHistoryOK { gateHistoryOK = false; showingHistory = true }
        }) {
            ParentalGateView(onSuccess: { gateHistoryOK = true })
        }
        .sheet(isPresented: $showingHistory) { WakeHistoryView() }

        // Parental gate → AlarmIOView
        .sheet(isPresented: $showingGateForIO, onDismiss: {
            if gateIOOK { gateIOOK = false; showingIO = true }
        }) {
            ParentalGateView(onSuccess: { gateIOOK = true })
        }
        .sheet(isPresented: $showingIO) { AlarmIOView() }
    }
}

#Preview {
    SettingsView()
}
