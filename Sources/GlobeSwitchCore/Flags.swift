import Foundation

/// The flag emoji for an ISO 3166 region code, such as "UA" → 🇺🇦; nil for anything else, so
/// that "EN" stays text instead of becoming a flag that doesn't exist.
public func flagEmoji(region: String) -> String? {
    let code = region.uppercased()
    let letters = code.unicodeScalars
    guard letters.count == 2, letters.allSatisfy({ ("A"..."Z").contains($0) }),
          Locale.Region.isoRegions.contains(Locale.Region(code)) else { return nil }
    let base: UInt32 = 0x1F1E6 - 0x41 // regional indicator symbol letter A, minus "A"
    return String(String.UnicodeScalarView(letters.compactMap { Unicode.Scalar(base + $0.value) }))
}

/// Keyboard layouts named after a country whose flag differs from their language's usual one,
/// matched by the start of the name after "com.apple.keylayout.".
private let layoutRegions: [(prefix: String, region: String)] = [
    ("British", "GB"), ("Australian", "AU"), ("Canadian", "CA"), ("Irish", "IE"),
    ("Swiss", "CH"), ("Austrian", "AT"), ("Belgian", "BE"), ("Portuguese", "PT"),
]

/// What the indicator shows for a layout.
public enum LayoutFlag: Equatable, CustomStringConvertible {
    /// The flag of an ISO 3166 region, such as "UA".
    case region(String)
    /// Text of the user's own from `LayoutFlags`, shown as it is.
    case text(String)

    /// The region's flag emoji, or the text.
    public var description: String {
        switch self {
        case .region(let code): return flagEmoji(region: code) ?? code
        case .text(let text): return text
        }
    }
}

/// The flag the indicator shows for a layout: the user's choice in `LayoutFlags` (a region code
/// such as "GB", or any text), a country the layout is named after (British → 🇬🇧), or the usual
/// region of its first language (uk → 🇺🇦, en → 🇺🇸). Nil when none of these gives a flag.
public func layoutFlag(id: String, languages: [String], overrides: [String: String] = [:]) -> LayoutFlag? {
    if let choice = overrides[id] {
        return region(choice) ?? .text(choice)
    }
    let name = id.components(separatedBy: ".").last ?? id
    if let match = layoutRegions.first(where: { name.hasPrefix($0.prefix) }) {
        return .region(match.region)
    }
    guard let language = languages.first else { return nil }
    let maximal = Locale.Language(identifier: language).maximalIdentifier
    return Locale.Language(identifier: maximal).region.flatMap { region($0.identifier) }
}

/// `.region` for a code that has a flag.
private func region(_ code: String) -> LayoutFlag? {
    flagEmoji(region: code) == nil ? nil : .region(code.uppercased())
}
