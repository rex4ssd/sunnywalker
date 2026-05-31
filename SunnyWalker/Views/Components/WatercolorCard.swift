// SunnyWalker — WatercolorCard.swift  |  Day 1  |  frosted-watercolor card container

import SwiftUI

struct WatercolorCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    init(cornerRadius: CGFloat = 24, @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(GhibliColors.cloudWhite.opacity(0.92))
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            )
    }
}

#Preview {
    WatercolorCard {
        VStack(spacing: 8) {
            Text("07:30")
                .font(GhibliFonts.clock(40))
                .foregroundStyle(GhibliColors.nightIndigo)
            Text("上學囉 · 一 二 三 四 五")
                .font(GhibliFonts.caption())
                .foregroundStyle(GhibliColors.totoroGray)
        }
        .padding()
    }
    .padding()
    .background(GhibliColors.skyBlue)
}
