// SunnyWalker — SunnyWalkerApp.swift  |  Day 1  |  app entry + SwiftData container

import SwiftUI
import SwiftData

@main
struct SunnyWalkerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Alarm.self)
    }
}
