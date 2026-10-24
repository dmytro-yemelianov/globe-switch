import Carbon
import Foundation
import GlobeSwitchCore

func sourceID(_ source: TISInputSource) -> String? {
    stringProperty(source, kTISPropertyInputSourceID)
}

func localizedName(_ source: TISInputSource) -> String? {
    stringProperty(source, kTISPropertyLocalizedName)
}

/// The languages a layout types, most important first.
func languages(_ source: TISInputSource) -> [String] {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return [] }
    return Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String] ?? []
}

/// How the indicator and the doctor show a layout: its flag, if it has one, and its name.
func flagAndName(_ source: TISInputSource, overrides: [String: String]) -> (flag: String?, name: String) {
    let id = sourceID(source) ?? "?"
    return (layoutFlag(id: id, languages: languages(source), overrides: overrides), localizedName(source) ?? id)
}

private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

func currentSourceID() -> String {
    sourceID(TISCopyCurrentKeyboardInputSource().takeRetainedValue()) ?? "?"
}

/// Enabled, selectable keyboard layouts and input modes — no emoji palette, dictation or press-and-hold.
func keyboardLayouts() -> [TISInputSource] {
    let filter: [String: Any] = [
        kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
        kTISPropertyInputSourceIsSelectCapable as String: true,
    ]
    let typing: Set<String> = [kTISTypeKeyboardLayout as String, kTISTypeKeyboardInputMode as String]
    guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else {
        return []
    }
    return list.filter { stringProperty($0, kTISPropertyInputSourceType).map(typing.contains) ?? false }
}
