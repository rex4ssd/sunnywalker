// SunnyWalker — ContentView.swift  |  Day 0  |  bootstrap root view

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("☀️")
                .font(.system(size: 64))
            Text("SunnyWalker")
                .font(.largeTitle.bold())
            Text("Day 0 — bootstrap complete")
                .foregroundStyle(.secondary)
            Text("AI A will start coding from here on Day 1.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
