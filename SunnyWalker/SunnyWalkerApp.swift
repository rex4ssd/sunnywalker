// SunnyWalker — SunnyWalkerApp.swift  |  Day 2  |  app entry + SwiftData container + permission bootstrap

import SwiftUI
import SwiftData

@main
struct SunnyWalkerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await PermissionManager.shared.requestAllPermissions()
                }
        }
        .modelContainer(for: Alarm.self)
    }
}
