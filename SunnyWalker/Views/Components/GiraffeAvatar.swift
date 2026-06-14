// SunnyWalker — GiraffeAvatar.swift
// Cute giraffe mascot drawn in pure SwiftUI shapes (no asset).
// Redesigned 2026-06-14: a proper long neck that connects body→head, big sweet
// eyes with highlights, rosy cheeks, soft patches, and legs.
// Same blink cadence + ClosedEye blink as the other mascots; keeps the original
// outer frame footprint (120×160 + top padding) so Home/Reward layouts don't shift.
// Breathing + night-sleepy idle are driven centrally by MascotView.livingAvatar —
// this avatar deliberately has no own breath animation (would double-scale).

import SwiftUI

struct GiraffeAvatar: View {
    var forceBlink = false
    @State private var isBlinking = false
    private let blinkTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    // Palette — warm, soft, Ghibli-friendly
    private let bodyColor = Color(red: 0.97, green: 0.81, blue: 0.40)   // golden coat
    private let bodyShade = Color(red: 0.93, green: 0.74, blue: 0.30)   // legs / neck shade
    private let bodyHi     = Color(red: 0.99, green: 0.90, blue: 0.62)  // belly highlight
    private let spotColor  = Color(red: 0.80, green: 0.52, blue: 0.22)  // soft brown patches
    private let muzzle      = Color(red: 0.99, green: 0.91, blue: 0.74) // light snout
    private let hoofColor   = Color(red: 0.55, green: 0.38, blue: 0.18)
    private let cheek       = Color(red: 0.97, green: 0.69, blue: 0.66)
    private let ink         = Color(red: 0.28, green: 0.20, blue: 0.12)

    var body: some View {
        ZStack {
            legs
            neck
            bodyShape
            head
        }
        .frame(width: 120, height: 160)
        // Ossicones reach a touch above the frame; the top padding gives the layout
        // back that overflow so the date text above never gets covered.
        .padding(.top, 52)
        .accessibilityLabel("長頸鹿")
        .accessibilityHint("SunnyWalker 吉祥物")
        .onReceive(blinkTimer) { _ in
            withAnimation(.easeIn(duration: 0.07)) { isBlinking = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                withAnimation(.easeOut(duration: 0.07)) { isBlinking = false }
            }
        }
    }

    // MARK: - Big parts

    private var legs: some View {
        HStack(spacing: 20) {
            leg
            leg
        }
        .offset(y: 60)
    }

    private var leg: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(bodyShade)
            .frame(width: 15, height: 30)
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(hoofColor)
                    .frame(width: 15, height: 9)
            }
    }

    // Long neck that emerges from behind the body and carries the head. Drawn before
    // the body so its base tucks behind the chest for a clean join.
    private var neck: some View {
        RoundedRectangle(cornerRadius: 15)
            .fill(bodyColor)
            .frame(width: 30, height: 74)
            .overlay(
                VStack(spacing: 12) {
                    Ellipse().fill(spotColor).frame(width: 13, height: 10)
                    Ellipse().fill(spotColor).frame(width: 11, height: 9)
                }
                .offset(x: 1, y: -6)
            )
            .rotationEffect(.degrees(-8))
            .offset(x: -4, y: -16)
    }

    private var bodyShape: some View {
        ZStack {
            Ellipse()
                .fill(bodyColor)
                .frame(width: 88, height: 60)
            Ellipse()
                .fill(bodyHi)
                .frame(width: 52, height: 30)
                .offset(y: 12)
            Ellipse().fill(spotColor).frame(width: 20, height: 15).offset(x: -24, y: -4)
            Ellipse().fill(spotColor).frame(width: 16, height: 12).offset(x: 20, y: -8)
            Ellipse().fill(spotColor).frame(width: 15, height: 11).offset(x: 9, y: 14)
            Ellipse().fill(spotColor).frame(width: 13, height: 10).offset(x: -12, y: 16)
        }
        .offset(y: 32)
    }

    private var head: some View {
        ZStack {
            // Ears (behind the head oval)
            HStack(spacing: 52) {
                ear(flip: false)
                ear(flip: true)
            }
            .offset(y: -2)

            // Ossicones (horns)
            HStack(spacing: 20) {
                ossicone
                ossicone
            }
            .offset(y: -26)

            // Head oval
            Ellipse()
                .fill(bodyColor)
                .frame(width: 58, height: 50)

            // Head patch
            Ellipse()
                .fill(spotColor)
                .frame(width: 15, height: 11)
                .offset(x: 11, y: -12)

            // Muzzle with nostrils + smile
            Ellipse()
                .fill(muzzle)
                .frame(width: 34, height: 24)
                .overlay(
                    VStack(spacing: 3) {
                        HStack(spacing: 10) {
                            Capsule().fill(spotColor.opacity(0.55)).frame(width: 4, height: 6)
                            Capsule().fill(spotColor.opacity(0.55)).frame(width: 4, height: 6)
                        }
                        ClosedEye(color: ink.opacity(0.6), width: 14, height: 5, lineWidth: 2)
                    }
                    .offset(y: 2)
                )
                .offset(y: 15)

            // Cheeks
            HStack(spacing: 34) {
                Circle().fill(cheek).frame(width: 11, height: 11)
                Circle().fill(cheek).frame(width: 11, height: 11)
            }
            .offset(y: 7)

            // Eyes
            HStack(spacing: 20) {
                eye
                eye
            }
            .offset(y: -3)
        }
        .offset(y: -48)
    }

    // MARK: - Small parts

    @ViewBuilder
    private var eye: some View {
        if isBlinking || forceBlink {
            ClosedEye(color: ink.opacity(0.85), width: 16, height: 9, lineWidth: 2.4)
        } else {
            ZStack {
                Circle().fill(Color.white).frame(width: 15, height: 15)
                Circle().fill(ink).frame(width: 9, height: 9)
                Circle().fill(Color.white.opacity(0.95))
                    .frame(width: 3.5, height: 3.5)
                    .offset(x: 2, y: -2.5)
            }
        }
    }

    private var ossicone: some View {
        VStack(spacing: 0.5) {
            Circle()
                .fill(spotColor)
                .frame(width: 8, height: 8)
            RoundedRectangle(cornerRadius: 2.5)
                .fill(bodyColor)
                .frame(width: 5.5, height: 12)
        }
    }

    private func ear(flip: Bool) -> some View {
        Ellipse()
            .fill(bodyColor)
            .frame(width: 16, height: 24)
            .overlay(
                Ellipse()
                    .fill(spotColor.opacity(0.25))
                    .frame(width: 8, height: 14)
            )
            .rotationEffect(.degrees(flip ? 26 : -26))
    }
}

#Preview {
    GiraffeAvatar()
        .padding(40)
        .background(SunnyColors.wheatGold.opacity(0.3))
}
