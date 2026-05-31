// SunnyWalker — PermissionManager.swift  |  Day 3  |  centralized permission requests

import UserNotifications
import AVFoundation
import Speech
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    private init() {}

    @Published var notificationsGranted = false

    // MARK: - All permissions (call once on first launch)

    func requestAllPermissions() async {
        await requestNotificationPermission()
        await requestMicrophonePermission()
        await requestSpeechPermission()
    }

    // MARK: - Individual requests

    func requestNotificationPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            notificationsGranted = granted
        } catch {
            notificationsGranted = false
        }
    }

    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsGranted = settings.authorizationStatus == .authorized
    }

    func requestMicrophonePermission() async {
        _ = await AVAudioApplication.requestRecordPermission()
    }

    func requestSpeechPermission() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in cont.resume() }
        }
    }
}
