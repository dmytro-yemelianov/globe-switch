import Foundation

/// A flag drawn as pixel art for the indicator: one colour letter per pixel on a grid shared by
/// every flag, so they are all the same rectangle with the same pixel size. The flags live in
/// `corpus` as text and are read from it only when one is shown.
public struct PixelFlag: Equatable {
    public static let width = 22
    public static let height = 14

    /// Colours as 0xRRGGBB, by the letter the rows use for them; "." is transparent.
    let colors: [Character: UInt32]
    /// Top row first.
    let rows: [String]

    /// The flag of an ISO 3166 region such as "UA", or nil when the corpus has none.
    public init?(region: String) {
        let code = region.uppercased()
        guard let block = Self.corpus.split(separator: "\n\n").first(where: { $0.hasPrefix(code + " ") }) else {
            return nil
        }
        let lines = block.split(separator: "\n")
        if let alias = lines[0].range(of: " = ") {
            guard let flag = PixelFlag(region: String(lines[0][alias.upperBound...])) else { return nil }
            self = flag
            return
        }
        guard lines.count == Self.height + 2 else { return nil }
        var colors: [Character: UInt32] = [:]
        for pair in lines[1].split(separator: " ") {
            guard let letter = pair.first, let value = UInt32(pair.dropFirst(2), radix: 16) else { return nil }
            colors[letter] = value
        }
        let rows = lines.dropFirst(2).map(String.init)
        guard rows.allSatisfy({ $0.count == Self.width }) else { return nil }
        self.colors = colors
        self.rows = rows
    }

    /// Every region the corpus has a flag for, including those that fly another region's flag.
    static var regions: [String] {
        corpus.split(separator: "\n\n").map { String($0.prefix(2)) }
    }

    /// The pixels as 8-bit RGBA with premultiplied alpha, top row first.
    public var rgba: [UInt8] {
        rows.flatMap { row in
            row.flatMap { letter -> [UInt8] in
                guard letter != ".", let color = colors[letter] else { return [0, 0, 0, 0] }
                return [UInt8(color >> 16 & 0xFF), UInt8(color >> 8 & 0xFF), UInt8(color & 0xFF), 0xFF]
            }
        }
    }
}
