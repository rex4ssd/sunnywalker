// SunnyWalker — SunnyButton.swift  |  Day 1  |  primary tappable button

import SwiftUI

struct SunnyButton: View {
    let title: LocalizedStringKey
    let color: Color
    let action: () -> Void

    init(_ title: LocalizedStringKey, color: Color = SunnyColors.lanternOrange, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(SunnyFonts.button())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(color)
                        .shadow(color: color.opacity(0.4), radius: 8, y: 4)
                )
        }
        .ghibliButtonStyle()
    }
}

#Preview {
    VStack(spacing: 16) {
        SunnyButton("起床囉！", color: SunnyColors.lanternOrange) {}
        SunnyButton("好的，知道了", color: SunnyColors.leafFresh) {}
        SunnyButton("設定", color: SunnyColors.sunnyGray) {}
    }
    .padding()
    .background(SunnyColors.skyBlue)
}
