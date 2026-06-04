// SunnyWalker — RewardView.swift  |  Day 27  |  Accessibility + reduceMotion

import SwiftUI
import ConfettiSwiftUI

struct RewardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confettiCounter = 0

    // Celebration animation state
    @State private var wiggle = false
    @State private var totoroScale: CGFloat = 0.3
    @State private var textScale: CGFloat = 0.5
    @State private var textOpacity: Double = 0
    @State private var starsVisible = false

    var body: some View {
        ZStack {
            SunnyColors.wheatGold
                .ignoresSafeArea()

            // Decorative star burst behind mascot
            if starsVisible {
                starBurst
                    .transition(.opacity)
            }

            VStack(spacing: 32) {
                Spacer()

                // Title bounces in from below
                Text("你好棒！🌟")
                    .font(SunnyFonts.title(40))
                    .foregroundStyle(SunnyColors.forestDeep)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .scaleEffect(textScale)
                    .opacity(textOpacity)

                // Mascot: bounces in + perpetual happy wiggle (suppressed with reduceMotion)
                MascotView()
                    .scaleEffect(reduceMotion ? 1.0 : totoroScale)
                    .rotationEffect(
                        .degrees(reduceMotion ? 0 : (wiggle ? 12 : -12)),
                        anchor: .bottom
                    )
                    .animation(
                        reduceMotion ? .none : .easeInOut(duration: 0.4).repeatForever(autoreverses: true),
                        value: wiggle
                    )
                    .accessibilityHidden(true)

                Text("早安！新的一天開始囉 ☀️")
                    .font(SunnyFonts.body(20))
                    .foregroundStyle(SunnyColors.forestDeep.opacity(0.75))
                    .opacity(textOpacity)

                Spacer()
            }
        }
        .confettiCannon(
            counter: $confettiCounter,
            num: 60,
            colors: [
                SunnyColors.lanternOrange,
                SunnyColors.starGold,
                SunnyColors.leafFresh,
                SunnyColors.skyBlue,
                SunnyColors.cloudWhite
            ],
            confettiSize: 10,
            radius: 420
        )
        .onAppear {
            if reduceMotion {
                totoroScale = 1.0; textScale = 1.0; textOpacity = 1.0; starsVisible = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { totoroScale = 1.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { wiggle = true }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.15)) {
                    textScale = 1.0; textOpacity = 1.0
                }
                withAnimation(.easeIn(duration: 0.3).delay(0.25)) { starsVisible = true }
            }
            confettiCounter += 1
        }
        .task {
            try? await Task.sleep(for: .seconds(3.5))
            dismiss()
        }
    }

    // MARK: - Star burst decoration

    private var starBurst: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Image(systemName: "star.fill")
                    .font(.system(size: CGFloat.random(in: 12...22)))
                    .foregroundStyle(SunnyColors.starGold.opacity(Double.random(in: 0.5...0.9)))
                    .offset(
                        x: cos(Double(i) * .pi / 4) * 130,
                        y: sin(Double(i) * .pi / 4) * 130
                    )
            }
        }
        .frame(width: 1, height: 1)  // zero-size anchor; stars radiate outward
    }
}

#Preview {
    RewardView()
}
