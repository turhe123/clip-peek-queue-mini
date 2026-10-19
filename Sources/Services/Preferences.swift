import Foundation
import Carbon.HIToolbox

/// Central list of `UserDefaults` / `@AppStorage` keys and their default values.
enum Prefs {
    static let inspectKeyCode = "inspectKeyCode"
    static let inspectModifiers = "inspectModifiers"
    static let inspectKeyName = "inspectKeyName"
    static let pasteKeyCode = "pasteKeyCode"
    static let pasteModifiers = "pasteModifiers"
    static let pasteKeyName = "pasteKeyName"
    static let tipDuration = "tipDuration"
    static let autoReduce = "autoReduce"
    static let excludedApps = "excludedApps"
    static let explainedAccessibility = "explainedAccessibility"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            inspectKeyCode: kVK_ANSI_V,
            inspectModifiers: controlKey | optionKey,
            inspectKeyName: "V",
            pasteKeyCode: kVK_ANSI_V,
            pasteModifiers: controlKey | optionKey | shiftKey,
            pasteKeyName: "V",
            tipDuration: 5.0,
            autoReduce: false,
            excludedApps: "",
        ])
    }

    /// Bundle identifiers (one per line) where automatic reduction is skipped.
    static var excludedBundleIDs: Set<String> {
        let raw = UserDefaults.standard.string(forKey: excludedApps) ?? ""
        return Set(raw.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    /// Human-readable shortcut such as "⌃⌥⇧V" from Carbon modifier flags.
    static func shortcutText(modifiers: Int, key: String) -> String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + key
    }

    static func shortcutText(modsKey: String, nameKey: String) -> String {
        let d = UserDefaults.standard
        return shortcutText(modifiers: d.integer(forKey: modsKey), key: d.string(forKey: nameKey) ?? "?")
    }
}
