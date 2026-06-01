// SunnyWalker — Localization.swift  |  i18n: String Catalog + runtime language override
//
// Two localization paths kept in sync by one stored choice (UserDefaults "appLanguageCode"):
//
//   1. SwiftUI `Text(LocalizedStringKey)` / `Button("literal")` etc. localize automatically
//      from Localizable.xcstrings, driven by the `\.locale` environment value that
//      `SunnyWalkerApp` injects from `LocalizationManager.locale`.
//
//   2. Plain strings produced OUTSIDE SwiftUI (models, services, AlarmKit titles,
//      notification bodies) cannot see the environment locale, so they call the global
//      `L(_:)` helper, which loads the matching `.lproj` bundle for the chosen language.
//
// "system" = follow the device language (the default).

import SwiftUI
import Foundation

// MARK: - Supported languages

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    /// Key into Localizable.xcstrings for the human-readable language name.
    var displayKey: LocalizedStringKey {
        switch self {
        case .system:             return "lang_system"
        case .english:            return "lang_english"
        case .traditionalChinese: return "lang_chinese"
        }
    }
}

// MARK: - Observable manager (drives the SwiftUI environment locale)

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    static let storageKey = "appLanguageCode"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        language = AppLanguage(rawValue: raw) ?? .system
    }

    /// Locale injected into the SwiftUI environment so `Text` re-localizes live on change.
    var locale: Locale {
        switch language {
        case .system:             return Locale.autoupdatingCurrent
        case .english:            return Locale(identifier: "en")
        case .traditionalChinese: return Locale(identifier: "zh-Hant")
        }
    }
}

// MARK: - Non-SwiftUI lookup (thread-safe; reads UserDefaults + bundle)

/// Bundle / locale resolution that mirrors `LocalizationManager` for code that runs off the
/// main actor or outside the view hierarchy. Safe to call from any thread.
enum SunnyLocalization {
    static var code: String {
        UserDefaults.standard.string(forKey: LocalizationManager.storageKey) ?? AppLanguage.system.rawValue
    }
    static var locale: Locale {
        code == AppLanguage.system.rawValue ? .current : Locale(identifier: code)
    }
    static var bundle: Bundle {
        guard code != AppLanguage.system.rawValue,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

/// Localize a key for the chosen app language. Falls back to the key itself (the zh-Hant
/// source string) when no translation exists.
func L(_ key: String) -> String {
    SunnyLocalization.bundle.localizedString(forKey: key, value: key, table: nil)
}

/// Localize a `String(format:)` key with arguments, e.g. `L("import_result %lld", count)`.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = SunnyLocalization.bundle.localizedString(forKey: key, value: key, table: nil)
    return String(format: format, locale: SunnyLocalization.locale, arguments: arguments)
}

// MARK: - Reusable language picker (used in the parent-gated settings screen)

struct LanguagePickerSection: View {
    @ObservedObject private var manager = LocalizationManager.shared

    var body: some View {
        Picker("language_setting", selection: $manager.language) {
            ForEach(AppLanguage.allCases) { lang in
                Text(lang.displayKey).tag(lang)
            }
        }
    }
}
