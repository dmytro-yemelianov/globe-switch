import AppKit
import GlobeSwitchCore

/// The short sound after each switch (`PlaySound`, `Sound`, `SoundVolume`). The built-in click is
/// pitched for the layout switched to; any other sound plays the same for every layout. A quick
/// second tap restarts the sound instead of layering a second one over it.
enum SwitchSound {
    static let builtIn = "Click"
    private static var clicks: [Int: NSSound] = [:]
    private static var reported: Set<String> = []

    /// `layoutIndex` is the new layout's place among the enabled layouts.
    static func play(_ name: String, volume: Double, layoutIndex: Int) {
        guard let sound = name == builtIn ? click(for: layoutIndex) : NSSound(named: NSSound.Name(name)) else {
            if reported.insert(name).inserted {
                log("sound \(name) not found in /System/Library/Sounds or ~/Library/Sounds", .error)
            }
            return
        }
        sound.stop()
        sound.volume = Float(volume)
        if !sound.play() && reported.insert(name).inserted {
            log("sound \(name) could not be played", .error)
        }
    }

    private static func click(for layoutIndex: Int) -> NSSound? {
        if let sound = clicks[layoutIndex] { return sound }
        let sound = NSSound(data: Click.wav(frequency: Click.frequency(forLayoutAt: layoutIndex)))
        clicks[layoutIndex] = sound
        return sound
    }
}
