// SunnyWalker — AppSettings.swift  |  Day 30  |  Shared app preferences

import Foundation
import SwiftUI

// MARK: - Mascot theme

enum MascotTheme: String, CaseIterable, Identifiable {
    case sunny    = "sunny"
    case giraffe  = "giraffe"
    case bunny    = "bunny"
    case bear     = "bear"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sunny:   return "小晴（灰色精靈）"
        case .giraffe: return "長頸鹿"
        case .bunny:   return "小兔子"
        case .bear:    return "小熊"
        }
    }

    var icon: String {
        switch self {
        case .sunny:   return "moon.stars.fill"
        case .giraffe: return "pawprint.fill"
        case .bunny:   return "hare.fill"
        case .bear:    return "teddybear.fill"
        }
    }
}

/// App-wide preferences stored in UserDefaults.
/// Observed by views via @ObservedObject so UI reacts to changes live.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private init() {
        // 12h/24h: default to the device's own clock convention
        if let stored = UserDefaults.standard.object(forKey: "use24HourClock") as? Bool {
            self.use24HourClock = stored
        } else {
            // Probe the system locale's hour cycle
            let probe = DateFormatter()
            probe.dateStyle = .none
            probe.timeStyle = .short
            probe.locale = Locale.current
            self.use24HourClock = probe.dateFormat.contains("H")
        }
        self.recordingGapSeconds = UserDefaults.standard.object(forKey: "recordingGapSeconds") as? Int ?? 2
        self.alarmRingDurationMinutes = UserDefaults.standard.object(forKey: "alarmRingDurationMinutes") as? Int ?? 5
        self.backgroundListeningEnabled = UserDefaults.standard.object(forKey: "backgroundListeningEnabled") as? Bool ?? false
        let raw = UserDefaults.standard.string(forKey: "mascotTheme") ?? MascotTheme.sunny.rawValue
        self.mascotTheme = MascotTheme(rawValue: raw) ?? .sunny
        self.parentalUnlockDurationMinutes = UserDefaults.standard.object(forKey: "parentalUnlockDurationMinutes") as? Int ?? 5
        let unlockedUntil = UserDefaults.standard.double(forKey: "parentalUnlockUntil")
        if unlockedUntil > Date().timeIntervalSince1970 {
            self.parentalUnlockUntil = Date(timeIntervalSince1970: unlockedUntil)
        } else {
            self.parentalUnlockUntil = nil
        }
    }

    // MARK: - Time format

    /// true = show 14:05 · false = show 2:05 PM
    @Published var use24HourClock: Bool {
        didSet { UserDefaults.standard.set(use24HourClock, forKey: "use24HourClock") }
    }

    // MARK: - Recording playback

    /// Seconds of silence between recording loops (gives child a moment to speak).
    /// Range 0–5; stored so parent can tune it in Settings.
    @Published var recordingGapSeconds: Int {
        didSet { UserDefaults.standard.set(recordingGapSeconds, forKey: "recordingGapSeconds") }
    }

    // MARK: - Alarm ring duration

    /// How long the alarm keeps ringing before it auto-stops and lets the screen sleep.
    /// Range 1–10 minutes. Prevents the battery draining if the child isn't there to wake.
    @Published var alarmRingDurationMinutes: Int {
        didSet { UserDefaults.standard.set(alarmRingDurationMinutes, forKey: "alarmRingDurationMinutes") }
    }

    // MARK: - Background listening (experimental, OFF by default)

    /// When ON, the app keeps a microphone session alive (foreground-started) so the child can
    /// voice-stop the alarm while the screen is off / app is backgrounded — like a recorder app.
    /// ⚠️ Keeps the orange mic indicator lit and uses the mic continuously; off by default.
    @Published var backgroundListeningEnabled: Bool {
        didSet { UserDefaults.standard.set(backgroundListeningEnabled, forKey: "backgroundListeningEnabled") }
    }

    // MARK: - Mascot theme

    @Published var mascotTheme: MascotTheme {
        didSet { UserDefaults.standard.set(mascotTheme.rawValue, forKey: "mascotTheme") }
    }

    @Published var parentalUnlockDurationMinutes: Int {
        didSet { UserDefaults.standard.set(parentalUnlockDurationMinutes, forKey: "parentalUnlockDurationMinutes") }
    }

    @Published private(set) var parentalUnlockUntil: Date? {
        didSet {
            let timestamp = parentalUnlockUntil?.timeIntervalSince1970 ?? 0
            UserDefaults.standard.set(timestamp, forKey: "parentalUnlockUntil")
        }
    }

    func beginParentalUnlockWindow() {
        parentalUnlockUntil = Date().addingTimeInterval(Double(parentalUnlockDurationMinutes * 60))
    }

    func clearExpiredParentalUnlockIfNeeded(referenceDate: Date = .now) {
        if let unlockedUntil = parentalUnlockUntil, unlockedUntil <= referenceDate {
            parentalUnlockUntil = nil
        }
    }

    func isParentalGateUnlocked(referenceDate: Date = .now) -> Bool {
        clearExpiredParentalUnlockIfNeeded(referenceDate: referenceDate)
        return remainingParentalUnlockSeconds(referenceDate: referenceDate) > 0
    }

    func remainingParentalUnlockSeconds(referenceDate: Date = .now) -> Int {
        guard let unlockedUntil = parentalUnlockUntil else { return 0 }
        return max(0, Int(unlockedUntil.timeIntervalSince(referenceDate)))
    }
}
