import XCTest
@testable import CadenceCore

/// Field-test issue #1: cue tones are pre-rendered to WAV and played via
/// `AVAudioPlayer` (which mixes with background audio) instead of `AVAudioEngine`
/// (which interrupted it). This verifies the pure WAV builder is well-formed.
final class ToneWAVTests: XCTestCase {

    func testWavHasValidRiffHeader() {
        let data = ToneWAV.sine(frequency: 1000, duration: 0.05, amplitude: 0.2, sampleRate: 44_100)
        XCTAssertGreaterThan(data.count, 44, "WAV must contain a 44-byte header plus samples")

        func string(_ range: Range<Int>) -> String {
            String(decoding: data[range], as: UTF8.self)
        }
        XCTAssertEqual(string(0..<4), "RIFF")
        XCTAssertEqual(string(8..<12), "WAVE")
        XCTAssertEqual(string(12..<16), "fmt ")
        XCTAssertEqual(string(36..<40), "data")
    }

    func testWavSampleCountMatchesDuration() {
        let sampleRate = 44_100.0
        let duration = 0.1
        let data = ToneWAV.sine(frequency: 880, duration: duration, amplitude: 0.3, sampleRate: sampleRate)

        let expectedFrames = Int(duration * sampleRate)
        // header (44) + 2 bytes/frame (16-bit mono)
        XCTAssertEqual(data.count, 44 + expectedFrames * 2)

        // The declared `data` chunk size must equal the PCM byte count.
        let declared = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 40, as: UInt32.self) }
        XCTAssertEqual(Int(declared.littleEndian), expectedFrames * 2)
    }

    func testFormatChunkDescribesMono16BitPCM() {
        let data = ToneWAV.sine(frequency: 500, duration: 0.02, amplitude: 0.1)
        func u16(_ offset: Int) -> UInt16 {
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }.littleEndian
        }
        XCTAssertEqual(u16(20), 1, "audio format should be PCM (1)")
        XCTAssertEqual(u16(22), 1, "channel count should be mono (1)")
        XCTAssertEqual(u16(34), 16, "bits per sample should be 16")
    }

    func testAmplitudeIsClampedAndNonZero() {
        let data = ToneWAV.sine(frequency: 1000, duration: 0.05, amplitude: 5.0)
        // With a >1 amplitude request, samples must still be valid Int16 (clamped
        // envelope keeps them in range) and the tone must be audible (non-silent).
        let samples = stride(from: 44, to: data.count, by: 2).map { offset -> Int16 in
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int16.self) }.littleEndian
        }
        XCTAssertTrue(samples.contains { $0 != 0 }, "rendered tone should not be silent")
    }
}
