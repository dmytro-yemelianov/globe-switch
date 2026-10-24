import Foundation
import GlobeSwitchCore

private let hiToolbox = "com.apple.HIToolbox" as CFString
private let fnUsageKey = "AppleFnUsageType" as CFString
private let ownDomain = GlobeSwitch.label as CFString
private let previousFnUsageKey = "PreviousFnUsageType" as CFString

/// The raw "Press 🌐 key to" value, read fresh: System Settings may have changed it since the last read.
func fnUsageSetting() -> Int? {
    CFPreferencesAppSynchronize(hiToolbox)
    return CFPreferencesCopyAppValue(fnUsageKey, hiToolbox) as? Int
}

/// Writes "Press 🌐 key to"; nil removes the value, which brings back the macOS default.
func setFnUsageSetting(_ value: Int?) {
    CFPreferencesSetAppValue(fnUsageKey, value.map { NSNumber(value: $0) }, hiToolbox)
    CFPreferencesAppSynchronize(hiToolbox)
}

/// The user's settings, read fresh so that `defaults write` takes effect on the next 🌐 press.
func readSettings() -> Settings {
    CFPreferencesAppSynchronize(ownDomain)
    var values: [String: Any] = [:]
    for key in Settings.keys {
        if let value = CFPreferencesCopyAppValue(key as CFString, ownDomain) { values[key] = value }
    }
    return Settings(values: values)
}

/// What 🌐 did before the first install, so uninstall can put it back.
enum PreviousFnUsage: Equatable {
    case value(Int)
    /// The setting was missing, so macOS used its default.
    case unset

    static func load() -> PreviousFnUsage? {
        CFPreferencesAppSynchronize(ownDomain)
        switch CFPreferencesCopyAppValue(previousFnUsageKey, ownDomain) {
        case let number as Int: return .value(number)
        case let string as String where string == "unset": return .unset
        default: return nil
        }
    }

    func save() {
        switch self {
        case .value(let number): CFPreferencesSetAppValue(previousFnUsageKey, NSNumber(value: number), ownDomain)
        case .unset: CFPreferencesSetAppValue(previousFnUsageKey, "unset" as CFString, ownDomain)
        }
        CFPreferencesAppSynchronize(ownDomain)
    }

    static func forget() {
        CFPreferencesSetAppValue(previousFnUsageKey, nil, ownDomain)
        CFPreferencesAppSynchronize(ownDomain)
    }
}
