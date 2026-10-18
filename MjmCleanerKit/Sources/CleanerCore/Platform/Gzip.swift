import CZlib
import Foundation

public enum GzipError: Error, Equatable, Sendable {
    case zlib(Int32)
}

/// Formato gzip (RFC 1952) tramite la zlib di sistema: Foundation non scrive gzip, e il log di
/// sessione deve restare leggibile con `gzip -dc` (su macOS `zcat` legge solo il formato `.Z`).
public enum Gzip {
    private static let chunkSize = 64 * 1024

    public static func compress(_ data: Data) throws -> Data {
        var stream = z_stream()
        // windowBits 15 + 16: intestazione e coda gzip invece del formato zlib.
        let initStatus = deflateInit2_(&stream, Z_BEST_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY,
                                       ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { throw GzipError.zlib(initStatus) }
        defer { deflateEnd(&stream) }
        return try pump(&stream, input: data) { deflate(&$0, Z_FINISH) }
    }

    public static func decompress(_ data: Data) throws -> Data {
        var stream = z_stream()
        // windowBits 15 + 32: riconosce da sé l'intestazione gzip.
        let initStatus = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { throw GzipError.zlib(initStatus) }
        defer { inflateEnd(&stream) }
        return try pump(&stream, input: data) { inflate(&$0, Z_NO_FLUSH) }
    }

    /// Fa scorrere `input` attraverso `step` a blocchi finché zlib non segnala la fine dello
    /// stream. Qualunque altro esito (dati troncati o corrotti) è un errore.
    private static func pump(
        _ stream: inout z_stream,
        input: Data,
        step: (inout z_stream) -> Int32
    ) throws -> Data {
        var source = [UInt8](input)
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var output = Data()
        let inputCount = source.count

        let status: Int32 = source.withUnsafeMutableBufferPointer { inputPointer in
            stream.next_in = inputPointer.baseAddress
            stream.avail_in = uInt(inputCount)
            var result = Z_OK
            while result == Z_OK {
                result = buffer.withUnsafeMutableBufferPointer { outputPointer in
                    guard let base = outputPointer.baseAddress else { return Z_MEM_ERROR }
                    stream.next_out = base
                    stream.avail_out = uInt(chunkSize)
                    let stepResult = step(&stream)
                    output.append(base, count: chunkSize - Int(stream.avail_out))
                    return stepResult
                }
            }
            return result
        }

        guard status == Z_STREAM_END else { throw GzipError.zlib(status) }
        return output
    }
}
