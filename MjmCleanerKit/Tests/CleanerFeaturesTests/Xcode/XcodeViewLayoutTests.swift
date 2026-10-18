import CleanerCore
import Testing
@testable import CleanerFeatures

/// Le prove di `XcodeViewLayoutTests.cs` ridotte a ciò che il modello garantisce: i titoli dei
/// gruppi, il testo dell'anteprima, le anteprime grandi e l'identità delle righe del resoconto.
/// Che pulsanti e controlli restino nel viewport è della vista (piano 4b, spec §9.4).
@MainActor
struct XcodeViewLayoutTests {
    private typealias Fixture = XcodeViewModelTests

    @Test func nonEmptyPageRendersFourGroupsAndFinalConfirmationLabels() async throws {
        let model = Fixture.create(Fixture.FakeXcode(Fixture.snapshot(
            Fixture.candidate("derived", .derivedData), Fixture.candidate("support", .deviceSupport),
            Fixture.candidate("device", .device), Fixture.candidate("runtime", .runtime))))
        await model.initialLoad?.value
        try Fixture.onlyRow(model, .device).isSelected = true

        #expect(model.groups.map(\.title) == ["DerivedData", "Device Support", "Dispositivi simulati", "Runtime iOS, watchOS, tvOS e visionOS"])

        model.preview()

        #expect(model.previewSummaryText == "Risorse selezionate: 1")
        #expect(model.previewEstimateText == "Stima nota: 100 B")
    }

    @Test func largeConfirmationKeepsDestructiveAndBackControlsInViewport() async throws {
        let candidates = (0..<100).map { Fixture.candidate(String(format: "device-%03d", $0), .device) }
        let model = Fixture.create(Fixture.FakeXcode(XcodeSnapshot(candidates: candidates, warnings: [])))
        await model.initialLoad?.value
        for row in try Fixture.group(model, .device).rows { row.isSelected = true }

        model.preview()

        #expect(model.confirmation?.selectedCandidates.count == 100)
        #expect(model.canConfirmDelete)
    }

    @Test func largeRetainedDependencyListKeepsFinalControlsInViewport() async throws {
        let names = (0..<100).map { String(format: "dependent-%03d", $0) }
        let candidates = [Fixture.candidate("runtime", .runtime, dependencies: names)] + names.map { Fixture.candidate($0, .device) }
        let model = Fixture.create(Fixture.FakeXcode(XcodeSnapshot(candidates: candidates, warnings: [])))
        await model.initialLoad?.value
        try Fixture.onlyRow(model, .runtime).isSelected = true

        model.preview()

        #expect(model.confirmation?.retainedDependentDevices.count == 100)
        #expect(!model.canConfirmDelete)
    }

    @Test func reportRowsRenderResourceIdentity() async {
        let uuid = "11111111-1111-4111-8111-111111111111"
        let candidate = XcodeCandidate(key: "device:" + uuid, kind: .device, name: "iPhone 16", cliId: uuid)
        let result = XcodeCleanResult(
            historyReport: makeReport(),
            items: [XcodeItemResult(candidate: candidate, outcome: .deleted, reason: "verified", verifiedEstimatedBytes: 100)],
            freeBytesBefore: 100, freeBytesAfter: 120, warnings: [])
        let model = XcodeReportModel(
            history: FakeHistory(), sessionLog: FakeSessionLog(), navigation: Fixture.FakeNavigation(), result: result, journal: nil)
        await model.persistence?.value

        #expect(model.items.map(\.identity) == [uuid])
        #expect(model.items.map(\.name) == ["iPhone 16"])
    }
}
