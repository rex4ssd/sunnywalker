// SunnyWalker — RewardView.swift  |  Day 4  |  success celebration screen (auto-dismisses after 3s)

import SwiftUI

struct RewardView: View {
    @Environment(\.dismiss) private var dismiss

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
        .task {
            try? await Task.sleep(for: .seconds(3))
            dismiss()
        }
    }
}

#Preview {
    RewardView()
}
