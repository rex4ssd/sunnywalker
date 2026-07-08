// SunnyWalker — AppSettings.swift  |  Day 30  |  Shared app preferences

import Foundation
import SwiftUI

// MARK: - Feature limits (free vs Pro)

/// Single source of truth for every monetizable cap in the app. The free tier enforces these;
/// the paid (Pro) version unlocks them by flipping `isPro` to true — ideally wired to StoreKit /
/// a purchased entitlement later. KEEP ALL CAPS HERE so adding Pro is a one-switch change and so
/// code review can see the whole free/paid boundary in one place. See 03_todo_fectures.md.
///
/// Semantics: `Int.max` / `.infinity` mean "effectively unlimited" — call sites that schedule a
/// timer or pass a duration MUST check `.isFinite` before using the recording caps.
enum FeatureLimits {
    /// Whether the user owns Pro. Backed by UserDefaults("isProUnlocked"), which is set from the
    /// StoreKit entitlement OR the one-time grandfather grant for pre-paid installs. See `StoreService`.
    /// WRITE ONLY through `StoreService` (the sole owner of entitlement state); tests may toggle it.
    /// Read here (not @Published) so off-main code — AudioRecorder, schedulers — sees the same value.
    static var isPro: Bool {
        get { UserDefaults.standard.bool(forKey: StoreService.proUnlockedKey) }
        set { UserDefaults.standard.set(newValue, forKey: StoreService.proUnlockedKey) }
    }

    // Free-tier baselines + the one finite Pro value. Named so the caps below AND the Pro upsell
    // copy (ProUpgradeView) read the same numbers — no literal cap is hardcoded in any view.
    static let freeMaxAlarms = 10
    static let freeMaxVoiceClips = 5
    static let freeMaxVoiceClipSeconds: Double = 5
    static let proMaxVoiceClipSeconds: Double = 30
    static let freeMaxAlarmRecordingSeconds: TimeInterval = 180

    /// Max number of alarms a parent can keep at once.
    static var maxAlarms: Int { isPro ? .max : freeMaxAlarms }

    /// Max number of saved voice clips in the library ("自定鈴聲").
    static var maxVoiceClips: Int { isPro ? .max : freeMaxVoiceClips }

    /// Max length of a single library voice clip, in seconds.
    static var maxVoiceClipSeconds: Double { isPro ? proMaxVoiceClipSeconds : freeMaxVoiceClipSeconds }

    /// Max length of a per-alarm parent recording, in seconds. `.infinity` for Pro (no auto-stop).
    static var maxAlarmRecordingSeconds: TimeInterval { isPro ? .infinity : freeMaxAlarmRecordingSeconds }
}

// MARK: - Mascot theme

enum MascotTheme: String, CaseIterable, Identifiable {
    case sunnyAlarm = "sunnyAlarm"
    case sunny    = "sunny"
    case giraffe  = "giraffe"
    case bunny    = "bunny"
    case bear     = "bear"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sunnyAlarm: return "小鬧晴"
        case .sunny:   return "小晴（灰色精靈）"
        case .giraffe: return "長頸鹿"
        case .bunny:   return "小兔子"
        case .bear:    return "小熊"
        }
    }

    var icon: String {
        switch self {
        case .sunnyAlarm: return "alarm.fill"
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

    /// End the temporary unlock immediately ("立即上鎖") — next Settings / New Alarm re-shows the gate.
    func endParentalUnlockWindow() {
        parentalUnlockUntil = nil
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
