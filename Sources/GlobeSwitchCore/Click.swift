import Foundation

/// The built-in switch sound: a soft 40 ms click, synthesized rather than recorded, pitched a little
/// differently for each layout so the ear can tell them apart.
public enum Click {
    public static let baseFrequency = 1_600.0
    /// Semitones above the base for the layouts in system order: the notes of a major chord, then
    /// the octave, then round again.
    static let steps = [0, 4, 7, 12]

    /// The pitch for the layout at `index` among the enabled layouts.
    public static func frequency(forLayoutAt index: Int) -> Double {
        let step = steps[((index % steps.count) + steps.count) % steps.count]
        return baseFrequency * pow(2, Double(step) / 12)
    }

    /// A mono 16-bit WAV of the click at `frequency`: a damped tone with one overtone, a 0.6 ms
    /// attack and a 5.5 ms exponential decay.
    public static func wav(frequency: Double, sampleRate: Double = 44_100, duration: Double = 0.040) -> Data {
        let count = Int(sampleRate * duration)
        var pcm = Data(capacity: count * 2)
        for n in 0..<count {
            let t = Double(n) / sampleRate
            let envelope = min(1, t / 0.0006) * exp(-t / 0.0055)
            let tone = sin(2 * .pi * frequency * t) + 0.35 * sin(2 * .pi * 2 * frequency * t + 0.6)
            let sample = Int16(max(-1, min(1, 0.7 * envelope * tone)) * Double(Int16.max))
            pcm += littleEndian(sample)
        }
        var wav = Data("RIFF".utf8) + littleEndian(UInt32(36 + pcm.count)) + Data("WAVE".utf8)
        wav += Data("fmt ".utf8) + littleEndian(UInt32(16)) + littleEndian(UInt16(1)) + littleEndian(UInt16(1))
        wav += littleEndian(UInt32(sampleRate)) + littleEndian(UInt32(sampleRate) * 2)
        wav += littleEndian(UInt16(2)) + littleEndian(UInt16(16))
        wav += Data("data".utf8) + littleEndian(UInt32(pcm.count)) + pcm
        return wav
    }

    private static func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
