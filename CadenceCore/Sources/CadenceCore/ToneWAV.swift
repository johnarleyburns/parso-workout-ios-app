import Foundation

/// Pure, dependency-free builder for short sine-wave cue tones as 16-bit PCM
/// WAV data. Kept in `CadenceCore` so it is headlessly testable with
/// `swift test` (the app plays the result via `AVAudioPlayer`, which — unlike
/// `AVAudioEngine` — reliably mixes with the user's background audio).
public enum ToneWAV {
    /// A mono 16-bit PCM WAV `Data` for a sine tone with a short linear
    /// attack/decay envelope (avoids clicks). `amplitude` is 0...1.
    public static func sine(frequency: Double,
                            duration: Double,
                            amplitude: Double,
                            sampleRate: Double = 44_100) -> Data {
        let frameCount = max(1, Int(duration * sampleRate))
        let envelopeSeconds = 0.005

        var samples = [Int16]()
        samples.reserveCapacity(frameCount)
        let amp = max(0, min(1, amplitude))
        for i in 0 ..< frameCount {
            let t = Double(i) / sampleRate
            let attack = min(t / envelopeSeconds, 1.0)
            let release = min((duration - t) / envelopeSeconds, 1.0)
            let envelope = max(0, min(attack, release, 1.0))
            let value = amp * envelope * sin(2 * .pi * frequency * t)
            samples.append(Int16((value * Double(Int16.max)).rounded()))
        }

        return wav(from: samples, sampleRate: sampleRate)
    }

    /// Wraps 16-bit mono PCM samples in a canonical 44-byte WAV/RIFF header.
    static func wav(from samples: [Int16], sampleRate: Double) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = UInt16(channels * bitsPerSample / 8)
        let dataBytes = samples.count * MemoryLayout<Int16>.size

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))

        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))              // PCM subchunk size
        append(UInt16(1))              // audio format = PCM
        append(channels)
        append(UInt32(sampleRate))
        append(byteRate)
        append(blockAlign)
        append(bitsPerSample)

        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataBytes))
        for sample in samples {
            append(sample)
        }

        return data
    }
}
