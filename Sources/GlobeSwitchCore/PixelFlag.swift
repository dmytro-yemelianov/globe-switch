import Foundation

/// A flag drawn as pixel art for the indicator: one colour letter per pixel on a grid shared by
/// every flag, so they are all the same rectangle with the same pixel size. A region without one
/// shows its emoji flag.
public struct PixelFlag: Equatable {
    public static let width = 22
    public static let height = 14

    /// Colours as 0xRRGGBB, by the letter the rows use for them.
    let colors: [Character: UInt32]
    /// Top row first.
    let rows: [String]

    /// The flags drawn so far, by ISO 3166 region code.
    public static let byRegion: [String: PixelFlag] = ["UA": ukraine, "GB": unitedKingdom]

    /// The pixels as opaque 8-bit RGBA, top row first.
    public var rgba: [UInt8] {
        rows.flatMap { row in
            row.flatMap { letter -> [UInt8] in
                let color = colors[letter] ?? 0
                return [UInt8(color >> 16 & 0xFF), UInt8(color >> 8 & 0xFF), UInt8(color & 0xFF), 0xFF]
            }
        }
    }
}

extension PixelFlag {
    static let ukraine = PixelFlag(colors: ["B": 0x0057B7, "Y": 0xFFD700], rows: [
        "BBBBBBBBBBBBBBBBBBBBBB",
        "BBBBBBBBBBBBBBBBBBBBBB",
        "BBBBBBBBBBBBBBBBBBBBBB",
        "BBBBBBBBBBBBBBBBBBBBBB",
        "BBBBBBBBBBBBBBBBBBBBBB",
        "BBBBBBBBBBBBBBBBBBBBBB",
        "BBBBBBBBBBBBBBBBBBBBBB",
        "YYYYYYYYYYYYYYYYYYYYYY",
        "YYYYYYYYYYYYYYYYYYYYYY",
        "YYYYYYYYYYYYYYYYYYYYYY",
        "YYYYYYYYYYYYYYYYYYYYYY",
        "YYYYYYYYYYYYYYYYYYYYYY",
        "YYYYYYYYYYYYYYYYYYYYYY",
        "YYYYYYYYYYYYYYYYYYYYYY",
    ])

    /// Each arm of the red saltire is a one-pixel staircase with the broad white on one side and the
    /// narrow white on the other, swapped between the hoist and the fly as on the real flag.
    static let unitedKingdom = PixelFlag(colors: ["B": 0x012169, "W": 0xFFFFFF, "R": 0xC8102E], rows: [
        "RWWWBBBBBWRRWBBBBBWWRW",
        "WRWWWBBBBWRRWBBBBWRRWW",
        "BWRRWWWBBWRRWBBWWRWWWB",
        "BBWWRWWWWWRRWWWRRWWWBB",
        "BBBBWRRWWWRRWRRWWWBBBB",
        "WWWWWWWWWWRRWWWWWWWWWW",
        "RRRRRRRRRRRRRRRRRRRRRR",
        "RRRRRRRRRRRRRRRRRRRRRR",
        "WWWWWWWWWWRRWWWWWWWWWW",
        "BBBBWWWRRWRRWWWRRWBBBB",
        "BBWWWRRWWWRRWWWWWRWWBB",
        "BWWWRWWBBWRRWBBWWWRRWB",
        "WWRRWBBBBWRRWBBBBWWWRW",
        "WRWWBBBBBWRRWBBBBBWWWR",
    ])
}
