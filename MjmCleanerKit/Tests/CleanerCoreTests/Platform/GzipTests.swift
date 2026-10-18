import Foundation
import Testing
@testable import CleanerCore

struct GzipTests {
    @Test func roundTripsAndIsReadableByTheGzipCommand() throws {
        let text = String(repeating: #"{"path":"/Users/tester/Library/Caches/x"}"# + "\n", count: 5_000)
        let compressed = try Gzip.compress(Data(text.utf8))

        #expect(compressed.count < text.utf8.count / 10)
        #expect(compressed.prefix(2) == Data([0x1f, 0x8b]))
        #expect(String(decoding: try Gzip.decompress(compressed), as: UTF8.self) == text)

        // Su macOS `zcat` legge solo il formato `.Z`: il comando di riferimento è `gzip -dc`.
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let file = tmp.path + "/log.jsonl.gz"
        try compressed.write(to: URL(fileURLWithPath: file))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", file]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let decoded = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: decoded, as: UTF8.self) == text)
    }

    @Test func emptyInputProducesAValidEmptyArchive() throws {
        #expect(try Gzip.decompress(try Gzip.compress(Data())).isEmpty)
    }

    @Test func truncatedDataIsRejected() throws {
        let compressed = try Gzip.compress(Data(String(repeating: "abc", count: 10_000).utf8))
        #expect(throws: GzipError.self) { try Gzip.decompress(compressed.prefix(compressed.count / 2)) }
    }

    @Test func largeInputSpansManyChunks() throws {
        var bytes = [UInt8](repeating: 0, count: 1_000_000)
        for index in bytes.indices { bytes[index] = UInt8(truncatingIfNeeded: index &* 2_654_435_761 >> 13) }
        let data = Data(bytes)
        #expect(try Gzip.decompress(try Gzip.compress(data)) == data)
    }
}
