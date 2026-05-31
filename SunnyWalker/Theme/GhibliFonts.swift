// SunnyWalker — GhibliFonts.swift  |  Day 1  |  typography helpers

import SwiftUI

enum GhibliFonts {
    // Rounded system font fallback — feels child-friendly without a custom font file.
    // Swap .systemDesign to a registered custom font name once assets are added.
    static func title(_ size: CGFloat = 32) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func body(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .regular, design: .rounded)
    }

    static func button(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func caption(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func clock(_ size: CGFloat = 76) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func subtitle(_ size: CGFloat = 18) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
}
