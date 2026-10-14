import Testing
@testable import CleanerCore

struct XcodeClassifierTests {
    private func snapshot(_ candidates: XcodeCandidate...) -> XcodeSnapshot {
        XcodeSnapshot(candidates: candidates, warnings: [])
    }

    private func file(_ key: String, _ kind: XcodeResourceKind = .derivedData) -> XcodeCandidate {
        XcodeCandidate(key: key, kind: kind, name: key, sizeBytes: 5)
    }

    private func device(_ key: String, state: String = "Shutdown") -> XcodeCandidate {
        XcodeCandidate(key: key, kind: .device, name: "iPhone", cliId: key, runtimeIdentifier: "iOS 18", state: state, sizeBytes: 7)
    }

    private func runtime(_ key: String, dependencies: [String]? = nil) -> XcodeCandidate {
        XcodeCandidate(key: key, kind: .runtime, name: "iOS 18", cliId: "22222222-2222-4222-8222-222222222222", sizeBytes: 9, dependencies: dependencies)
    }

    private func single(_ candidates: [XcodeCandidate], _ kind: XcodeResourceKind? = nil) throws -> XcodeCandidate {
        let matching = candidates.filter { kind == nil || $0.kind == kind }
        #expect(matching.count == 1)
        return try #require(matching.first)
    }

    @Test func allRowsStartDeselected() throws {
        let classified = try XcodeClassifier.classify(snapshot(
            file("derived-data:/dd"), device("11111111-1111-4111-8111-111111111111"), runtime("runtime:22222222-2222-4222-8222-222222222222")), xcodeRunning: false)

        let preview = try XcodeSelection.preview(classified, selectedKeys: [])
        #expect(preview.selectedCandidates.isEmpty)
    }

    @Test func bootedDeviceAndItsRuntimeAreBlocked() throws {
        let booted = device("11111111-1111-4111-8111-111111111111", state: "Booted")
        let dependent = runtime("runtime:22222222-2222-4222-8222-222222222222", dependencies: [booted.key])

        let classified = try XcodeClassifier.classify(snapshot(booted, dependent), xcodeRunning: false)

        #expect(try !single(classified.candidates, .device).canSelect)
        #expect(try !single(classified.candidates, .runtime).canSelect)
    }

    @Test func unavailableDeviceWithVerifiedUuidRemainsSelectable() throws {
        var unavailable = device("11111111-1111-4111-8111-111111111111", state: "Unavailable")
        unavailable.blockReason = "Stato del dispositivo non verificato: Unavailable; ripeti l'analisi."

        let classified = try XcodeClassifier.classify(snapshot(unavailable), xcodeRunning: false)

        #expect(try single(classified.candidates).canSelect)
    }

    @Test func unavailableDevicePreservesUnrelatedSafetyBlock() throws {
        var unavailable = device("11111111-1111-4111-8111-111111111111", state: "Unavailable")
        unavailable.blockReason = "UUID duplicato con metadati in conflitto."

        let classified = try XcodeClassifier.classify(snapshot(unavailable), xcodeRunning: false)

        #expect(try single(classified.candidates).blockReason == "UUID duplicato con metadati in conflitto.")
    }

    @Test func deviceWithoutMatchingCliUuidIsBlocked() throws {
        var mismatched = device("11111111-1111-4111-8111-111111111111")
        mismatched.cliId = "33333333-3333-4333-8333-333333333333"

        let classified = try XcodeClassifier.classify(snapshot(mismatched), xcodeRunning: false)

        #expect(try !single(classified.candidates).canSelect)
    }

    @Test func xcodeRunningBlocksFileCleanup() throws {
        let classified = try XcodeClassifier.classify(
            snapshot(file("derived-data:/dd"), file("device-support:/ds", .deviceSupport)), xcodeRunning: true)

        #expect(classified.candidates.allSatisfy { !$0.canSelect })
    }
}
