import Foundation
import Compression

/// First-party gzip (`.gz`) compression built on Apple's `Compression`
/// framework (zlib deflate) plus a small gzip header/footer + CRC32 wrapper.
/// Zero third-party dependencies (NFR-6), and the output is a standard `.gz`
/// file every desktop OS can unpack — preserving the user's sovereignty over
/// their exported data.
public enum DataCompression {

    /// Guard against zip-bomb-style inputs: never inflate past 4 GB.
    public static let maxInflatedBytes = 4 * 1024 * 1024 * 1024

    public enum CompressionError: Error, Equatable {
        case deflateFailed
        case inflateFailed
        case truncated
        case inflatedTooLarge
    }

    // MARK: gzip

    /// Wraps raw deflate output in a standard gzip container (magic `1F 8B`,
    /// deflate method, mtime=0, plus the ISIZE + CRC32 footer).
    public static func gzip(_ data: Data) throws -> Data {
        let deflated = try rawDeflate(data)
        var out = Data()
        out.append(contentsOf: [0x1f, 0x8b, 0x08, 0x00,   // magic, deflate, no flags
                                0x00, 0x00, 0x00, 0x00,   // mtime = 0
                                0x00, 0xff])              // XFL=0, OS=unknown(255)
        out.append(deflated)
        var crc = crc32(data).littleEndian
        withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
        var isize = UInt32(truncatingIfNeeded: data.count).littleEndian
        withUnsafeBytes(of: &isize) { out.append(contentsOf: $0) }
        return out
    }

    /// Inflates a gzip container produced by `gzip(_:)` (or any standard tool).
    public static func gunzip(_ data: Data) throws -> Data {
        guard data.count >= 18, data[data.startIndex] == 0x1f,
              data[data.startIndex + 1] == 0x8b else {
            throw CompressionError.truncated
        }
        // Header is 10 bytes when no optional flags are set; skip any that are.
        let flags = data[data.startIndex + 3]
        var idx = data.startIndex + 10
        func need(_ n: Int) throws { if idx + n > data.endIndex - 8 { throw CompressionError.truncated } }
        if flags & 0x04 != 0 { // FEXTRA
            try need(2)
            let xlen = Int(data[idx]) | (Int(data[idx + 1]) << 8)
            idx += 2 + xlen
        }
        if flags & 0x08 != 0 { // FNAME
            while idx < data.endIndex && data[idx] != 0 { idx += 1 }
            idx += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while idx < data.endIndex && data[idx] != 0 { idx += 1 }
            idx += 1
        }
        if flags & 0x02 != 0 { idx += 2 } // FHCRC
        guard idx <= data.endIndex - 8 else { throw CompressionError.truncated }

        // Declared uncompressed size (ISIZE) is the last 4 bytes (mod 2^32).
        let footer = data.suffix(8)
        let isize = footer.suffix(4).reversed().reduce(0) { ($0 << 8) | Int($1) }
        let deflated = data[idx..<(data.endIndex - 8)]
        return try rawInflate(Data(deflated), expectedSize: isize)
    }

    // MARK: raw deflate/inflate (zlib algorithm, no header)

    static func rawDeflate(_ data: Data) throws -> Data {
        if data.isEmpty { return Data() }
        return try perform(operation: COMPRESSION_STREAM_ENCODE, source: data,
                           dstHint: max(64, data.count / 2))
    }

    static func rawInflate(_ data: Data, expectedSize: Int) throws -> Data {
        if data.isEmpty { return Data() }
        let hint = expectedSize > 0 ? min(expectedSize, maxInflatedBytes) : max(64, data.count * 4)
        return try perform(operation: COMPRESSION_STREAM_DECODE, source: data, dstHint: hint)
    }

    private static func perform(operation: compression_stream_operation,
                                source: Data, dstHint: Int) throws -> Data {
        var stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
                                        dst_size: 0,
                                        src_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
                                        src_size: 0,
                                        state: nil)
        guard compression_stream_init(&stream, operation, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw operation == COMPRESSION_STREAM_ENCODE ? CompressionError.deflateFailed : CompressionError.inflateFailed
        }
        defer { compression_stream_destroy(&stream) }

        let bufferSize = max(4096, min(dstHint, 1 << 20))
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dstBuffer.deallocate() }

        var output = Data()
        let result: Data? = source.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = srcRaw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.src_ptr = srcBase
            stream.src_size = source.count
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            repeat {
                stream.dst_ptr = dstBuffer
                stream.dst_size = bufferSize
                let status = compression_stream_process(&stream, flags)
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    let produced = bufferSize - stream.dst_size
                    if produced > 0 { output.append(dstBuffer, count: produced) }
                    if output.count > maxInflatedBytes { return nil }
                    if status == COMPRESSION_STATUS_END { return output }
                default:
                    return nil
                }
            } while true
        }
        guard let result else {
            throw operation == COMPRESSION_STREAM_ENCODE ? CompressionError.deflateFailed : CompressionError.inflateFailed
        }
        return result
    }

    // MARK: CRC32 (gzip footer integrity)

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
            return c
        }
    }()

    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
