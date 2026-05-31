// SunnyWalker — ContentView.swift  |  Day 2  |  root NavigationStack → HomeView

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            HomeView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Alarm.self, inMemory: true)
}
