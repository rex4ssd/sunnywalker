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
                    .fill(SunnyColors.cloudWhite.opacity(0.92))
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            )
    }
}

#Preview {
    WatercolorCard {
        VStack(spacing: 8) {
            Text("07:30")
                .font(SunnyFonts.clock(40))
                .foregroundStyle(SunnyColors.nightIndigo)
            Text("上學囉 · 一 二 三 四 五")
                .font(SunnyFonts.caption())
                .foregroundStyle(SunnyColors.sunnyGray)
        }
        .padding()
    }
    .padding()
    .background(SunnyColors.skyBlue)
}
