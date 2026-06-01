// SunnyWalker — RewardView.swift  |  Day 18  |  Totoro celebration animation

import SwiftUI
import ConfettiSwiftUI

struct RewardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confettiCounter = 0

    // Celebration animation state
    @State private var wiggle = false
    @State private var totoroScale: CGFloat = 0.3
    @State private var textScale: CGFloat = 0.5
    @State private var textOpacity: Double = 0
    @State private var starsVisible = false

    var body: some View {
        ZStack {
            GhibliColors.wheatGold
                .ignoresSafeArea()

            // Decorative star burst behind Totoro
            if starsVisible {
                starBurst
                    .transition(.opacity)
            }

            VStack(spacing: 32) {
                Spacer()

                // Title bounces in from below
                Text("你好棒！🌟")
                    .font(GhibliFonts.title(40))
                    .foregroundStyle(GhibliColors.forestDeep)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .scaleEffect(textScale)
                    .opacity(textOpacity)

                // Totoro: bounces in + perpetual happy wiggle
                TotoroAvatar()
                    .scaleEffect(totoroScale)
                    .rotationEffect(
                        .degrees(wiggle ? 12 : -12),
                        anchor: .bottom
                    )
                    .animation(
                        .easeInOut(duration: 0.4).repeatForever(autoreverses: true),
                        value: wiggle
                    )

                Text("早安！新的一天開始囉 ☀️")
                    .font(GhibliFonts.body(20))
                    .foregroundStyle(GhibliColors.forestDeep.opacity(0.75))
                    .opacity(textOpacity)

                Spacer()
            }
        }
        .confettiCannon(
            counter: $confettiCounter,
            num: 60,
            colors: [
                GhibliColors.lanternOrange,
                GhibliColors.starGold,
                GhibliColors.leafFresh,
                GhibliColors.skyBlue,
                GhibliColors.cloudWhite
            ],
            confettiSize: 10,
            radius: 420
        )
        .onAppear {
            // Stagger the entrance for a playful feel
            // 1. Totoro bounces in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                totoroScale = 1.0
            }
            // 2. Start wiggle after bounce settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                wiggle = true
            }
            // 3. Text fades + scales in shortly after
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.15)) {
                textScale = 1.0
                textOpacity = 1.0
            }
            // 4. Stars appear
            withAnimation(.easeIn(duration: 0.3).delay(0.25)) {
                starsVisible = true
            }
            // 5. Confetti
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
                    .foregroundStyle(GhibliColors.starGold.opacity(Double.random(in: 0.5...0.9)))
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
