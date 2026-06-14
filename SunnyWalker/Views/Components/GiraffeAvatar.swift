// SunnyWalker — GiraffeAvatar.swift
// Cute giraffe mascot drawn in pure SwiftUI shapes.
// Same blink timer cadence as SunnyAvatar.

import SwiftUI

struct GiraffeAvatar: View {
    var forceBlink = false
    @State private var isBlinking = false
    private let blinkTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    // Palette
    private let bodyColor   = Color(red: 0.96, green: 0.78, blue: 0.30)   // warm golden yellow
    private let spotColor   = Color(red: 0.60, green: 0.36, blue: 0.10)   // warm brown
    private let neckColor   = Color(red: 0.96, green: 0.78, blue: 0.30)

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Neck ──────────────────────────────────────────────
            RoundedRectangle(cornerRadius: 12)
                .fill(neckColor)
                .frame(width: 36, height: 60)
                .offset(y: 0)
                // Neck spot
                .overlay(
                    Ellipse()
                        .fill(spotColor)
                        .frame(width: 14, height: 10)
                        .offset(x: 2, y: -8)
                )

            // ── Body ──────────────────────────────────────────────
            Ellipse()
                .fill(bodyColor)
                .frame(width: 90, height: 76)
                .offset(y: 8)
                // Body spots
                .overlay(
                    ZStack {
                        Ellipse()
                            .fill(spotColor)
                            .frame(width: 20, height: 14)
                            .offset(x: -22, y: 0)
                        Ellipse()
                            .fill(spotColor)
                            .frame(width: 16, height: 12)
                            .offset(x: 18, y: -10)
                        Ellipse()
                            .fill(spotColor)
                            .frame(width: 14, height: 10)
                            .offset(x: 10, y: 14)
                        Ellipse()
                            .fill(spotColor)
                            .frame(width: 12, height: 9)
                            .offset(x: -10, y: 18)
                    }
                    .offset(y: 8)
                )

            // ── Head ──────────────────────────────────────────────
            ZStack {
                // Head oval
                Ellipse()
                    .fill(bodyColor)
                    .frame(width: 60, height: 52)

                // Ossicones (horns) — two short knobbed protrusions
                HStack(spacing: 22) {
                    ossicone
                    ossicone
                }
                .offset(y: -36)

                // Ears
                HStack(spacing: 54) {
                    ear(flip: false)
                    ear(flip: true)
                }
                .offset(y: -2)

                // Eyes
                HStack(spacing: 18) {
                    eye
                    eye
                }
                .offset(y: -4)

                // Snout bump
                Ellipse()
                    .fill(bodyColor.opacity(0.6))
                    .frame(width: 28, height: 18)
                    .overlay(
                        HStack(spacing: 8) {
                            Circle().fill(spotColor.opacity(0.5)).frame(width: 5, height: 5)
                            Circle().fill(spotColor.opacity(0.5)).frame(width: 5, height: 5)
                        }
                    )
                    .offset(y: 14)

                // Head spot
                Ellipse()
                    .fill(spotColor)
                    .frame(width: 16, height: 11)
                    .offset(x: 10, y: -12)
            }
            .offset(y: -94)  // sit on top of neck
        }
        .frame(width: 120, height: 160)
        // 頭 + 觸角用 offset(y:-94) 畫到 frame 外上方約 50pt（frame 半高僅 80），不 clip 會蓋到
        // 上方的日期文字。加 top padding 把溢出量補回佈局尺寸，讓上層 VStack 正確留出間距。
        .padding(.top, 52)
        .accessibilityLabel("長頸鹿")
        .accessibilityHint("SunnyWalker 吉祥物")
        .onReceive(blinkTimer) { _ in
            withAnimation(.easeIn(duration: 0.07))  { isBlinking = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                withAnimation(.easeOut(duration: 0.07)) { isBlinking = false }
            }
        }
    }

    // MARK: - Parts

    @ViewBuilder
    private var eye: some View {
        if isBlinking || forceBlink {
            ClosedEye(color: spotColor.opacity(0.9), width: 15, height: 8, lineWidth: 2.2)
        } else {
            Circle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .overlay(
                Circle()
                    .fill(Color.black)
                    .frame(width: 7, height: 7)
                )
        }
    }

    private var ossicone: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(spotColor)
                .frame(width: 7, height: 7)
            RoundedRectangle(cornerRadius: 2)
                .fill(spotColor)
                .frame(width: 5, height: 14)
        }
    }

    private func ear(flip: Bool) -> some View {
        Ellipse()
            .fill(bodyColor)
            .frame(width: 14, height: 22)
            .overlay(
                Ellipse()
                    .fill(spotColor.opacity(0.3))
                    .frame(width: 7, height: 13)
            )
            .rotationEffect(.degrees(flip ? 20 : -20))
    }
}

#Preview {
    GiraffeAvatar()
        .padding(40)
        .background(SunnyColors.wheatGold.opacity(0.3))
}
