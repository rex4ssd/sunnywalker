// SunnyWalker — ContentView.swift  |  Day 1  |  root view → HomeView

import SwiftUI

struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Alarm.self, inMemory: true)
}
