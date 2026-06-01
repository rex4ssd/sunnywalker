// SunnyWalker — GhibliButton.swift  |  Day 1  |  primary tappable button

import SwiftUI

struct GhibliButton: View {
    let title: LocalizedStringKey
    let color: Color
    let action: () -> Void

    init(_ title: LocalizedStringKey, color: Color = GhibliColors.lanternOrange, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(GhibliFonts.button())
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
        GhibliButton("起床囉！", color: GhibliColors.lanternOrange) {}
        GhibliButton("好的，知道了", color: GhibliColors.leafFresh) {}
        GhibliButton("設定", color: GhibliColors.totoroGray) {}
    }
    .padding()
    .background(GhibliColors.skyBlue)
}
