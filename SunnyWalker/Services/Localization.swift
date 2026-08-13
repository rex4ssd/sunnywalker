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

import AppLocalization
import Combine
import SwiftUI
import Foundation

// MARK: - Supported languages (shared engine, app-flavoured surface)

// The language enum now IS the shared library's LanguagePreference (system / en / zh-Hant —
// identical raw values to the old app-local AppLanguage, so stored choices carry over
// unchanged). Kept under the AppLanguage name so views/tests stay untouched.
typealias AppLanguage = LanguagePreference

extension LanguagePreference {
    /// Old app-local case names, preserved for call sites/tests (`.english` / `.traditionalChinese`).
    static let english = LanguagePreference.en
    static let traditionalChinese = LanguagePreference.zhHant

    /// Key into Localizable.xcstrings for the human-readable language name (app-specific keys).
    var displayKey: LocalizedStringKey {
        switch self {
        case .system: return "lang_system"
        case .en:     return "lang_english"
        case .zhHant: return "lang_chinese"
        }
    }
}

// MARK: - Observable manager (drives the SwiftUI environment locale)

// Thin ObservableObject facade over the shared AppLocalization.LanguageStore
// (see common_lib_ios/docs/sunnywalker_phase1_swap.md — behaviour-equivalent swap):
// same UserDefaults key ("appLanguageCode"), same stored raw values, and `.system`
// still resolves to `.autoupdatingCurrent` for the SwiftUI environment.
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    // nonisolated: SunnyLocalization (a nonisolated enum) reads this off the main actor. Without
    // nonisolated, Swift 6 mode errors on the cross-actor reference. Safe — an immutable Sendable
    // String constant can't race.
    nonisolated static let storageKey = "appLanguageCode"

    /// Shared single source of truth; keeps the legacy key (values are LanguagePreference-compatible).
    let store: LanguageStore

    // No @Published property — `language` derives from the store, so publish manually in the setter.
    let objectWillChange = ObservableObjectPublisher()

    private init() {
        store = LanguageStore(key: Self.storageKey)
        // Point the library-global Lang.store at the same instance so shared components
        // (KidsParentalUI / KidsFamilyShelf `L(zh,en)` strings) follow the app's language choice.
        Lang.store = store
    }

    /// Same external interface as before (AppLanguage == LanguagePreference).
    var language: AppLanguage {
        get { store.preference }
        set {
            objectWillChange.send()
            store.preference = newValue
        }
    }

    /// Locale injected into the SwiftUI environment (system → autoupdatingCurrent, as before).
    var locale: Locale { store.environmentLocale }
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
