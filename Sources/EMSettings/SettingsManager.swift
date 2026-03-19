import Foundation
import Observation
import EMCore

/// App-wide settings persisted in UserDefaults per [A-011].
/// Observable for SwiftUI binding per [A-010].
@MainActor
@Observable
public final class SettingsManager {
    private let defaults: UserDefaults

    // MARK: - Appearance

    /// User's preferred color scheme override. Nil means follow system.
    public var preferredColorScheme: ColorSchemePreference {
        didSet { defaults.set(preferredColorScheme.rawValue, forKey: Keys.colorScheme) }
    }

    // MARK: - Editor

    /// Whether spell checking is enabled.
    public var isSpellCheckEnabled: Bool {
        didSet { defaults.set(isSpellCheckEnabled, forKey: Keys.spellCheck) }
    }

    /// Whether auto-formatting is enabled.
    public var isAutoFormatEnabled: Bool {
        didSet { defaults.set(isAutoFormatEnabled, forKey: Keys.autoFormat) }
    }

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferredColorScheme = ColorSchemePreference(
            rawValue: defaults.string(forKey: Keys.colorScheme) ?? ""
        ) ?? .system
        self.isSpellCheckEnabled = defaults.object(forKey: Keys.spellCheck) as? Bool ?? true
        self.isAutoFormatEnabled = defaults.object(forKey: Keys.autoFormat) as? Bool ?? true
    }

    private enum Keys {
        static let colorScheme = "em_colorScheme"
        static let spellCheck = "em_spellCheck"
        static let autoFormat = "em_autoFormat"
    }
}

/// User's color scheme preference.
public enum ColorSchemePreference: String, Sendable, CaseIterable {
    case system
    case light
    case dark
}
