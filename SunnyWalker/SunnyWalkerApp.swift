// SunnyWalker — SunnyWalkerApp.swift  |  Day 2  |  app entry + SwiftData container + permission bootstrap

import SwiftUI
import SwiftData

@main
struct SunnyWalkerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await PermissionManager.shared.requestNotificationPermission()
                }
        }
        .modelContainer(for: Alarm.self)
    }
}
