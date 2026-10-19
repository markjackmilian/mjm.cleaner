import Foundation
import Testing
@testable import CleanerCore

struct UpdateVerifierTests {
    private static func download(in temp: TemporaryDirectory) throws -> DownloadedUpdate {
        let name = AvailableRelease.assetName(for: "v0.2.0")
        let release = AvailableRelease(
            version: AppVersion(major: 0, minor: 2, patch: 0),
            pageURL: try #require(URL(string: "https://github.com/markjackmilian/mjm.cleaner/releases/tag/v0.2.0")),
            assetName: name,
            assetURL: try #require(URL(string: "https://github.com/x/\(name)")),
            size: 3, sha256: String(repeating: "a", count: 64))
        let zip = try temp.file("v0.2.0/" + name, contents: "zip")
        return DownloadedUpdate(release: release, directory: temp.path + "/v0.2.0", zipPath: zip)
    }

    private func rejects(_ tools: FakeUpdateTools, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let download = try Self.download(in: temp)
        await #expect(sourceLocation: sourceLocation) {
            try await UpdateVerifier(runner: tools).verify(download)
        } throws: { error in
            if case .invalidBundle = error as? UpdateError { true } else { false }
        }
        #expect(!FileManager.default.fileExists(atPath: download.directory), "la cartella della release va cancellata", sourceLocation: sourceLocation)
    }

    @Test func acceptsTheUniversalReleaseBundleOfTheTag() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let download = try Self.download(in: temp)
        let tools = FakeUpdateTools(bundle: makeFakeBundle())
        let verified = try await UpdateVerifier(runner: tools).verify(download)

        let bundle = temp.path + "/v0.2.0/expanded/mjm.cleaner.app"
        #expect(verified == VerifiedUpdate(release: download.release, bundlePath: bundle))
        #expect(tools.calls.values == [
            ["/usr/bin/ditto", "-x", "-k", download.zipPath, temp.path + "/v0.2.0/expanded"],
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", bundle],
            ["/usr/bin/lipo", "-archs", bundle + "/Contents/MacOS/MjmCleaner"],
        ])
        #expect(tools.timeouts.values == [.seconds(120), .seconds(120), .seconds(30)])
        #expect(FileManager.default.isExecutableFile(atPath: bundle + "/Contents/MacOS/MjmCleaner"))
    }

    @Test func zipThatDoesNotExtractIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(), dittoExit: 1))
    }

    @Test func zipWithTwoItemsIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: { destination in
            try makeFakeBundle()(destination)
            FileManager.default.createFile(atPath: destination + "/extra", contents: Data())
        }))
    }

    @Test func zipWithoutAnAppIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(name: "mjm.cleaner")))
    }

    /// Il collegamento punta a un bundle che supererebbe ogni altro controllo: solo il tipo lo rifiuta.
    @Test func linkNamedLikeAnAppIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: { destination in
            let elsewhere = destination + "/../elsewhere"
            try makeFakeBundle()(elsewhere)
            try FileManager.default.createSymbolicLink(atPath: destination + "/mjm.cleaner.app", withDestinationPath: elsewhere + "/mjm.cleaner.app")
        }))
    }

    @Test func missingInfoPlistIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: { destination in
            try FileManager.default.createDirectory(atPath: destination + "/mjm.cleaner.app/Contents", withIntermediateDirectories: true)
        }))
    }

    @Test(arguments: ["com.mjm.cleaner.debug", "com.example.other"])
    func otherBundleIdentifierIsRejected(identifier: String) async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(identifier: identifier)))
    }

    @Test(arguments: ["0.1.0", "0.2.1", "v0.2.0"])
    func versionOtherThanTheTagIsRejected(version: String) async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(version: version)))
    }

    @Test func missingExecutableIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(executableIsPresent: false)))
    }

    @Test func executableOutsideMacOSIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(executable: "../MacOS/MjmCleaner")))
    }

    @Test func invalidSignatureIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(), codesignExit: 1))
    }

    @Test func signatureCheckThatTimesOutIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(), codesignTimesOut: true))
    }

    @Test(arguments: ["arm64\n", "x86_64\n", "", "arm64e x86_64\n"])
    func singleArchitectureBundleIsRejected(archs: String) async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(), archs: archs))
    }

    @Test func nonExecutableFileIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(permissions: 0o644)))
    }

    @Test(arguments: ["", ".", ".."]) func emptyOrDotExecutableIsRejected(executable: String) async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(executable: executable)))
    }

    @Test func lipoFailureIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(), lipoExit: 1))
    }

    /// Un'estrazione interrotta lascia file e cartelle: non devono sopravvivere al giro successivo.
    @Test func leftoversOfAPreviousExtractionAreCleared() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let download = try Self.download(in: temp)
        try temp.directory("v0.2.0/expanded/old.app")
        try temp.file("v0.2.0/expanded/stray")
        _ = try await UpdateVerifier(runner: FakeUpdateTools(bundle: makeFakeBundle())).verify(download)
        #expect(try FileManager.default.contentsOfDirectory(atPath: download.directory + "/expanded") == ["mjm.cleaner.app"])
    }
}
