// SunnyWalker — SunnyAvatar.swift  |  Day 2  |  forest-spirit mascot (blinks every 5 s)

import SwiftUI

struct SunnyAvatar: View {
    var forceBlink = false
    @State private var isBlinking = false

    // Timer.publish per spec §3.3 — drives the 5-second blink cadence
    private let blinkTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Body — rounded gray oval
            Ellipse()
                .fill(SunnyColors.sunnyGray)
                .frame(width: 100, height: 120)

            // Belly — lighter oval
            Ellipse()
                .fill(SunnyColors.cloudWhite.opacity(0.7))
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
        .accessibilityLabel("小晴")
        .accessibilityHint("SunnyWalker 吉祥物")
        .onReceive(blinkTimer) { _ in
            withAnimation(SunnyAnimations.blinkClose) { isBlinking = true }
            // 120 ms delay before reopening — GCD one-shot is the right tool here
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                withAnimation(SunnyAnimations.blinkOpen) { isBlinking = false }
            }
        }
    }

    @ViewBuilder
    private var eye: some View {
        if isBlinking || forceBlink {
            ClosedEye(color: Color.black.opacity(0.78), width: 18, height: 9, lineWidth: 2.4)
        } else {
            Circle()
                .fill(Color.white)
                .frame(width: 18, height: 18)
                .overlay(
                Circle()
                    .fill(Color.black)
                    .frame(width: 10, height: 10)
                )
        }
    }

    private var ear: some View {
        Triangle()
            .fill(SunnyColors.sunnyGray)
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
    SunnyAvatar()
        .padding(40)
        .background(SunnyColors.skyBlue)
}
