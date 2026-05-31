// SunnyWalker — RewardView.swift  |  Day 5  |  success celebration with pure-SwiftUI confetti

import SwiftUI

struct RewardView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            GhibliColors.wheatGold
                .ignoresSafeArea()

            ConfettiOverlay()

            VStack(spacing: 32) {
                Spacer()

                Text("你好棒！🌟")
                    .font(GhibliFonts.title(40))
                    .foregroundStyle(GhibliColors.forestDeep)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                TotoroAvatar()

                Spacer()
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(3))
            dismiss()
        }
    }
}

// MARK: - Pure-SwiftUI confetti: deterministic star particles falling from top

private struct ConfettiOverlay: View {
    @State private var animate = false

    // Deterministic layout — no random numbers, same every render
    private let xOffsets: [CGFloat] = [
        -160, -120, -80, -40,  0,  40,  80, 120, 160,
        -140, -100, -60, -20, 20,  60, 100, 140, -180, 180, 0
    ]
    private let delays: [Double] = [
        0.00, 0.10, 0.20, 0.05, 0.15, 0.25, 0.08, 0.18, 0.28,
        0.03, 0.13, 0.23, 0.07, 0.17, 0.27, 0.04, 0.14, 0.24, 0.09, 0.19
    ]
    private let sizes: [CGFloat] = [
        16, 20, 14, 18, 22, 16, 20, 14, 18, 12,
        20, 16, 14, 18, 22, 16, 12, 20, 14, 18
    ]
    private let icons: [String] = [
        "star.fill", "sparkles", "star.fill", "circle.fill", "star.fill",
        "sparkles", "star.fill", "circle.fill", "sparkles", "star.fill",
        "star.fill", "sparkles", "star.fill", "circle.fill", "star.fill",
        "sparkles", "star.fill", "circle.fill", "sparkles", "star.fill"
    ]
    private let colors: [Color] = [
        GhibliColors.lanternOrange, GhibliColors.starGold,  GhibliColors.leafFresh,
        GhibliColors.skyBlue,       GhibliColors.forestDeep, GhibliColors.lanternOrange,
        GhibliColors.starGold,      GhibliColors.leafFresh,  GhibliColors.skyBlue,
        GhibliColors.forestDeep,    GhibliColors.lanternOrange, GhibliColors.starGold,
        GhibliColors.leafFresh,     GhibliColors.skyBlue,    GhibliColors.forestDeep,
        GhibliColors.lanternOrange, GhibliColors.starGold,   GhibliColors.leafFresh,
        GhibliColors.skyBlue,       GhibliColors.forestDeep
    ]

    var body: some View {
        ZStack {
            ForEach(0..<20, id: \.self) { i in
                Image(systemName: icons[i])
                    .font(.system(size: sizes[i]))
                    .foregroundStyle(colors[i])
                    .offset(x: xOffsets[i], y: animate ? 700 : -80)
                    .animation(
                        .easeIn(duration: 1.4).delay(delays[i]),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

#Preview {
    RewardView()
}
