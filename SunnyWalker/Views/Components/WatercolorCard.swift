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
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.96),
                                    SunnyColors.cloudWhite.opacity(0.90),
                                    SunnyColors.wheatGold.opacity(0.11)
                                ],
                                center: .topLeading,
                                startRadius: 8,
                                endRadius: 360
                            )
                        )
                    PaperTextureOverlay(tint: SunnyColors.lanternOrange, density: 420)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(SunnyColors.forestDeep.opacity(0.10), lineWidth: 1)
                        .blur(radius: 0.35)
                }
                .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 6)
            )
    }
}

struct NavigationChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.callout.weight(.bold))
            .foregroundStyle(SunnyColors.sunnyGray.opacity(0.55))
            .frame(width: 36, height: 36)
            .background(
                Circle()
                    .fill(SunnyColors.sunnyGray.opacity(0.12))
            )
            .contentShape(Circle())
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
