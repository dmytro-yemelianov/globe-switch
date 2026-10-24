import Carbon
import Foundation

func sourceID(_ source: TISInputSource) -> String? {
    stringProperty(source, kTISPropertyInputSourceID)
}

func localizedName(_ source: TISInputSource) -> String? {
    stringProperty(source, kTISPropertyLocalizedName)
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
