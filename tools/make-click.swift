// make-click: synthesizes the switch sound, a soft 40 ms click, and writes App/Click.wav.
// Generated rather than recorded, so it carries no third-party audio.
//
//   swift tools/make-click.swift
import Foundation

let sampleRate = 44_100.0
let duration = 0.040
let count = Int(sampleRate * duration)

// A damped tone with one overtone: a short attack, then a fast exponential decay.
var samples: [Int16] = []
for n in 0..<count {
    let t = Double(n) / sampleRate
    let attack = min(1, t / 0.0006)
    let decay = exp(-t / 0.0055)
    let tone = sin(2 * .pi * 1_600 * t) + 0.35 * sin(2 * .pi * 3_200 * t + 0.6)
    samples.append(Int16(max(-1, min(1, 0.7 * attack * decay * tone)) * Double(Int16.max)))
}

func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
let dataSize = UInt32(samples.count * 2)
var wav = Data("RIFF".utf8) + le(UInt32(36) + dataSize) + Data("WAVE".utf8)
wav += Data("fmt ".utf8) + le(UInt32(16)) + le(UInt16(1)) + le(UInt16(1)) // PCM, mono
wav += le(UInt32(sampleRate)) + le(UInt32(sampleRate) * 2) + le(UInt16(2)) + le(UInt16(16))
wav += Data("data".utf8) + le(dataSize)
for sample in samples { wav += le(sample) }
try wav.write(to: URL(fileURLWithPath: "App/Click.wav"))
print("wrote App/Click.wav (\(count) samples)")
