import Foundation

public enum Appearance: String, Sendable {
    case dark
    case light

    /// `1` / `0`, the shape every wrapper script expects in `$DARKMODE`.
    public var environmentValue: String {
        self == .dark ? "1" : "0"
    }
}

public enum AppearanceReader {
    /// macOS records the setting as the *absence* of a key: `AppleInterfaceStyle`
    /// is "Dark" in dark mode and simply not there in light mode.
    public static let defaultsKey = "AppleInterfaceStyle"

    public static func appearance(from style: String?) -> Appearance {
        style?.lowercased() == "dark" ? .dark : .light
    }

    public static func current() -> Appearance {
        // Read through CFPreferences with an explicit synchronise rather than through
        // UserDefaults: this process outlives many theme switches, and a cached global
        // domain would keep answering with whatever was set when the agent started.
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyAppValue(defaultsKey as CFString, kCFPreferencesAnyApplication) as? String

        return appearance(from: style)
    }
}
