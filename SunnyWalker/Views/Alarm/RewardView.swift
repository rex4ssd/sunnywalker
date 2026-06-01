// SunnyWalker — RewardView.swift  |  Day 10  |  ConfettiSwiftUI particle cannon

import SwiftUI
import ConfettiSwiftUI

struct RewardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confettiCounter = 0

    var body: some View {
        ZStack {
            GhibliColors.wheatGold
                .ignoresSafeArea()

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
        .confettiCannon(
            counter: $confettiCounter,
            num: 50,
            colors: [
                GhibliColors.lanternOrange,
                GhibliColors.starGold,
                GhibliColors.leafFresh,
                GhibliColors.skyBlue
            ],
            confettiSize: 10,
            radius: 400
        )
        .task {
            confettiCounter += 1
            try? await Task.sleep(for: .seconds(3))
            dismiss()
        }
    }
}

#Preview {
    RewardView()
}
