// SunnyWalker — WakePhrase.swift  |  Day 1  |  recognized wake-up keywords

import Foundation

// Value-type (no persistence needed — set is fixed per locale).
struct WakePhrase {
    let text: String
    let locale: String  // BCP-47, e.g. "zh-TW"

    // Default Chinese keywords matching spec §4 Stage 4.
    // Kept as a static list so SpeechRecognizer can iterate without
    // hitting SwiftData on the audio thread.
    static let defaultKeywords: [WakePhrase] = [
        WakePhrase(text: "我起床了", locale: "zh-TW"),
        WakePhrase(text: "好的",    locale: "zh-TW"),
        WakePhrase(text: "知道了",  locale: "zh-TW"),
        WakePhrase(text: "起床囉",  locale: "zh-TW"),
    ]

    static var texts: [String] { defaultKeywords.map(\.text) }
}
