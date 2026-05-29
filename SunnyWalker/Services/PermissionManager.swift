// SunnyWalker — PermissionManager.swift  |  Day 2  |  centralized permission requests

import UserNotifications
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    private init() {}

    @Published var notificationsGranted = false

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
}
