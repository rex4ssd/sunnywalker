// SunnyWalker — AlarmRingView.swift  |  Day 3  |  full-screen alarm ring (visual shell)

import SwiftUI

struct AlarmRingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var wiggle = false

    private var scene: DaytimeScene {
        DaytimeScene.current(hour: Calendar.current.component(.hour, from: Date()))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scene.gradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            CloudBackground()

            VStack(spacing: 0) {
                Spacer()

                TotoroAvatar()
                    .rotationEffect(.degrees(wiggle ? 10 : -10), anchor: .bottom)
                    .animation(
                        .easeInOut(duration: 0.35).repeatForever(autoreverses: true),
                        value: wiggle
                    )
                    .padding(.bottom, 32)

                Text("該起床囉！☀️")
                    .font(GhibliFonts.title(28))
                    .foregroundStyle(scene.clockTextColor)
                    .padding(.bottom, 56)

                Spacer()

                GhibliButton("我起床了！", color: GhibliColors.lanternOrange) {
                    dismiss()
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 56)
            }
        }
        .onAppear { wiggle = true }
    }
}

#Preview {
    AlarmRingView()
}
