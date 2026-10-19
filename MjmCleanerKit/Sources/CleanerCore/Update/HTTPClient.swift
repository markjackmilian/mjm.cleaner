import Foundation

public struct HTTPResponse: Sendable, Equatable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// La rete dell'updater, astratta perché i test non la usino mai.
public protocol HTTPClient: Sendable {
    /// Una richiesta `GET`, con il corpo intero in memoria.
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse

    /// Scarica `url` nel file `destination`, che crea o sostituisce, e restituisce lo stato HTTP.
    /// `progress` riceve i byte scritti finora. Con uno stato diverso da 200 il file può restare
    /// parziale: lo cancella il chiamante.
    func download(_ url: URL, to destination: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> Int
}

/// `URLSession` effimera: niente cookie, cache o credenziali condivise con il resto del sistema.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        session = URLSession(configuration: configuration)
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        return HTTPResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }

    public func download(_ url: URL, to destination: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> Int {
        let (bytes, response) = try await session.bytes(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { return status }
        guard FileManager.default.createFile(atPath: destination, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination])
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: destination))
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        var written: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count == 1 << 16 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                progress(written)
            }
        }
        try handle.write(contentsOf: buffer)
        written += Int64(buffer.count)
        progress(written)
        return status
    }
}
