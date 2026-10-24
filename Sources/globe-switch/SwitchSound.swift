import AppKit

/// The short sound after each switch (`PlaySound`, `Sound`, `SoundVolume`). A quick second tap
/// restarts the sound instead of layering a second one over it.
enum SwitchSound {
    private static var reportedMissing: Set<String> = []

    static func play(_ name: String, volume: Double) {
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            if reportedMissing.insert(name).inserted {
                log("sound \(name) not found in the app, /System/Library/Sounds or ~/Library/Sounds", .error)
            }
            return
        }
        sound.stop()
        sound.volume = Float(volume)
        if !sound.play() && reportedMissing.insert(name).inserted {
            log("sound \(name) could not be played", .error)
        }
    }
}
