// SunnyWalker — TotoroAvatar.swift  |  Day 2  |  forest-spirit mascot (blinks every 5 s)

import SwiftUI

struct TotoroAvatar: View {
    @State private var isBlinking = false

    // Timer.publish per spec §3.3 — drives the 5-second blink cadence
    private let blinkTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Body — rounded gray oval
            Ellipse()
                .fill(GhibliColors.totoroGray)
                .frame(width: 100, height: 120)

            // Belly — lighter oval
            Ellipse()
                .fill(GhibliColors.cloudWhite.opacity(0.7))
                .frame(width: 60, height: 70)
                .offset(y: 14)

            // Eyes
            HStack(spacing: 20) {
                eye
                eye
            }
            .offset(y: -20)

            // Ears — two pointed triangles
            HStack(spacing: 54) {
                ear
                ear
            }
            .offset(y: -68)
        }
        .frame(width: 120, height: 140)
        .onReceive(blinkTimer) { _ in
            withAnimation(GhibliAnimations.blinkClose) { isBlinking = true }
            // 120 ms delay before reopening — GCD one-shot is the right tool here
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(GhibliAnimations.blinkOpen) { isBlinking = false }
            }
        }
    }

    private var eye: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 18, height: isBlinking ? 2 : 18)
            .overlay(
                Circle()
                    .fill(Color.black)
                    .frame(width: 10, height: 10)
                    .opacity(isBlinking ? 0 : 1)
            )
    }

    private var ear: some View {
        Triangle()
            .fill(GhibliColors.totoroGray)
            .frame(width: 22, height: 28)
    }
}

// Simple upward-pointing triangle shape
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

#Preview {
    TotoroAvatar()
        .padding(40)
        .background(GhibliColors.skyBlue)
}
