// SunnyWalker — MascotView.swift
// Drop-in replacement for SunnyAvatar() that respects the user's mascot theme setting.
// Use MascotView() everywhere instead of SunnyAvatar() directly.

import SwiftUI

struct MascotView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        switch settings.mascotTheme {
        case .sunny:   SunnyAvatar()
        case .giraffe: GiraffeAvatar()
        }
    }
}

#Preview {
    VStack(spacing: 32) {
        MascotView()
        Text("MascotView — switches with Settings")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding(40)
    .background(SunnyColors.skyBlue)
}
