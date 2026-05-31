// SunnyWalker — Animations.swift  |  Day 1  |  shared animation constants

import SwiftUI

enum GhibliAnimations {
    // Standard easing for interactive elements (button press, card toggle)
    static let snappy = Animation.spring(response: 0.35, dampingFraction: 0.7)

    // Slow float for clouds / background decorations
    static let cloudFloat = Animation.easeInOut(duration: 6).repeatForever(autoreverses: true)

    // Leaf rustle: quick wobble
    static let leafRustle = Animation.spring(response: 0.4, dampingFraction: 0.5)

    // Blink: instant close, slow open — mimics a real eyelid
    static let blinkClose = Animation.easeIn(duration: 0.08)
    static let blinkOpen  = Animation.easeOut(duration: 0.18)

    // Reward confetti burst
    static let confettiBurst = Animation.easeOut(duration: 0.6)
}

// MARK: - View Modifiers

struct ButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(GhibliAnimations.snappy, value: configuration.isPressed)
    }
}

extension View {
    func ghibliButtonStyle() -> some View {
        buttonStyle(ButtonPressStyle())
    }
}
