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
        case .bunny:   BunnyAvatar()
        case .bear:    BearAvatar()
        }
    }
}

private struct BunnyAvatar: View {
    @State private var isBlinking = false
    private let blinkTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color(red: 0.94, green: 0.90, blue: 0.98))
                .frame(width: 98, height: 116)

            Ellipse()
                .fill(Color.white.opacity(0.9))
                .frame(width: 58, height: 66)
                .offset(y: 16)

            HStack(spacing: 24) {
                bunnyEar
                bunnyEar
            }
            .offset(y: -76)

            HStack(spacing: 18) {
                eye
                eye
            }
            .offset(y: -14)

            Circle()
                .fill(Color(red: 0.98, green: 0.73, blue: 0.80))
                .frame(width: 10, height: 10)
                .offset(y: 4)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.black.opacity(0.75))
                .frame(width: 18, height: 3)
                .offset(y: 18)
        }
        .frame(width: 120, height: 150)
        .accessibilityLabel("小兔子")
        .onReceive(blinkTimer) { _ in
            withAnimation(.easeIn(duration: 0.07)) { isBlinking = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeOut(duration: 0.07)) { isBlinking = false }
            }
        }
    }

    private var eye: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 14, height: isBlinking ? 2 : 14)
            .overlay(
                Circle()
                    .fill(Color.black)
                    .frame(width: 7, height: 7)
                    .opacity(isBlinking ? 0 : 1)
            )
    }

    private var bunnyEar: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(red: 0.94, green: 0.90, blue: 0.98))
            .frame(width: 20, height: 56)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.98, green: 0.78, blue: 0.85))
                    .frame(width: 10, height: 36)
            )
    }
}

private struct BearAvatar: View {
    @State private var isBlinking = false
    private let blinkTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.62, green: 0.45, blue: 0.32))
                .frame(width: 100, height: 100)

            HStack(spacing: 56) {
                Circle()
                    .fill(Color(red: 0.62, green: 0.45, blue: 0.32))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(Color(red: 0.62, green: 0.45, blue: 0.32))
                    .frame(width: 28, height: 28)
            }
            .offset(y: -42)

            HStack(spacing: 56) {
                Circle()
                    .fill(Color(red: 0.83, green: 0.69, blue: 0.57))
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(Color(red: 0.83, green: 0.69, blue: 0.57))
                    .frame(width: 14, height: 14)
            }
            .offset(y: -42)

            Ellipse()
                .fill(Color(red: 0.88, green: 0.75, blue: 0.63))
                .frame(width: 52, height: 38)
                .offset(y: 20)

            HStack(spacing: 18) {
                eye
                eye
            }
            .offset(y: -4)

            Circle()
                .fill(Color.black.opacity(0.8))
                .frame(width: 9, height: 9)
                .offset(y: 14)
        }
        .frame(width: 120, height: 140)
        .accessibilityLabel("小熊")
        .onReceive(blinkTimer) { _ in
            withAnimation(.easeIn(duration: 0.07)) { isBlinking = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeOut(duration: 0.07)) { isBlinking = false }
            }
        }
    }

    private var eye: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 14, height: isBlinking ? 2 : 14)
            .overlay(
                Circle()
                    .fill(Color.black)
                    .frame(width: 7, height: 7)
                    .opacity(isBlinking ? 0 : 1)
            )
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
