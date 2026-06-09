// SunnyWalker — BedSideManager.swift  |  Day 20  |  UserDefaults brightness failsafe

import UIKit
import Foundation

/// Manages "bed-side mode": dims the screen to near-black and prevents auto-lock.
///
/// Force-quit failsafe: `enable()` persists `savedBrightness` to UserDefaults.
/// Call `restoreOnLaunch()` in AppDelegate to recover on next launch if the app
/// was killed while bed-side was active.
@MainActor
final class BedSideManager: ObservableObject {

    static let shared = BedSideManager()
    private init() {}

    @Published var isBedSideActive: Bool = false

    private var savedBrightness: CGFloat = 0.5   // default; actual value captured in enable()
    private let bedSideBrightness: CGFloat = 0.02
    private let udKey = "bedSideSavedBrightness"

    /// Returns the screen from the active window scene.
    /// Replaces deprecated `UIScreen.main` (iOS 26+).
    private var currentScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen
    }

    // MARK: - Enable

    func enable() {
        guard !isBedSideActive else { return }
        savedBrightness = currentScreen?.brightness ?? 0.5
        // Persist before dimming — failsafe for force-quit
        UserDefaults.standard.set(Double(savedBrightness), forKey: udKey)
        currentScreen?.brightness = bedSideBrightness
        UIApplication.shared.isIdleTimerDisabled = true
        isBedSideActive = true
        print("BedSideManager: enabled — dimmed, idleTimer off")
    }

    // MARK: - Disable

    func disable() {
        guard isBedSideActive else { return }
        currentScreen?.brightness = savedBrightness
        UIApplication.shared.isIdleTimerDisabled = false
        UserDefaults.standard.removeObject(forKey: udKey)
        isBedSideActive = false
        print("BedSideManager: disabled — brightness \(savedBrightness)")
    }

    // MARK: - Force-quit restore

    /// Call once in AppDelegate.application(_:didFinishLaunchingWithOptions:).
    /// If bed-side was active when the app was force-quit, restores brightness
    /// from UserDefaults and clears the stored key.
    func restoreOnLaunch() {
        guard let stored = UserDefaults.standard.object(forKey: udKey) as? Double else { return }
        let brightness = CGFloat(stored)
        currentScreen?.brightness = brightness
        UIApplication.shared.isIdleTimerDisabled = false
        UserDefaults.standard.removeObject(forKey: udKey)
        print("BedSideManager: restored brightness \(brightness) after force-quit")
    }
}
