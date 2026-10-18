import Testing
@testable import CleanerCore

struct DockerConfirmationGroupsTests {
    private func realCaseGroups() throws -> [DockerConfirmationGroup] {
        DockerConfirmationGroups.build(try DockerClassifier.classify(DockerFixtures.snapshot(), .empty))
    }

    @Test func groupsFollowTheRiskOrderAndSkipEmptyOnes() throws {
        #expect(try realCaseGroups().map(\.id) == [
            DockerConfirmationGroups.safeId,
            DockerConfirmationGroups.localBuildsId,
            DockerConfirmationGroups.unusedImagesId,
            DockerConfirmationGroups.unusedVolumesId,
            DockerConfirmationGroups.keepId,
        ])

        let onlyKeep = DockerConfirmationGroups.build([
            DockerCandidate(kind: .image, id: "sha256:1", displayName: "a", sizeBytes: 1, verdict: .keep, ruleId: "in-use", reason: "r", cost: "c"),
        ])
        #expect(onlyKeep.map(\.id) == [DockerConfirmationGroups.keepId])
    }

    @Test func safeDeletionsAreConfirmedAsABlock() throws {
        let safe = try #require(realCaseGroups().first { $0.id == DockerConfirmationGroups.safeId })

        #expect(safe.mode == .block)
        #expect(safe.selectedByDefault)
        #expect(DockerText.ordinalSorted(safe.items.map(\.displayName)) == [
            "Cache di build",
            "dcptun_developer_ms:0.25.13",
            "mcr.microsoft.com/azurelinux/base/core:3.0",
            "testcontainers/ryuk:0.14.0",
        ])
    }

    @Test func proposeAndAskGroupsStartUnselected() throws {
        for group in try realCaseGroups() where group.mode == .selectable {
            #expect(!group.selectedByDefault)
        }
    }

    @Test func keptResourcesAreReadOnly() throws {
        let keep = try #require(realCaseGroups().first { $0.id == DockerConfirmationGroups.keepId })

        #expect(keep.mode == .readOnly)
        #expect(keep.items.allSatisfy { $0.verdict == .keep })
    }

    @Test func unusedNamedVolumesNeedIndividualConfirmation() {
        let named = DockerCandidate(kind: .volume, id: "old", displayName: "old", sizeBytes: 1, verdict: .propose, ruleId: "named-unused", reason: "r", cost: "c")
        // `named with { Id = "anon", DisplayName = "anon", RuleId = "anonymous" }` del C#.
        let anonymous = DockerCandidate(kind: .volume, id: "anon", displayName: "anon", sizeBytes: 1, verdict: .propose, ruleId: "anonymous", reason: "r", cost: "c")

        #expect(DockerConfirmationGroups.requiresIndividualConfirmation(named))
        #expect(!DockerConfirmationGroups.requiresIndividualConfirmation(anonymous))
    }

    @Test func selectionNeverContainsKeptResources() throws {
        let groups = try realCaseGroups()
        let everything = Set(groups.flatMap(\.items))

        let selection = DockerConfirmationGroups.selection(groups, isGroupSelected: { _ in true }, isItemSelected: everything.contains)

        #expect(!selection.contains { $0.verdict == .keep })
        #expect(selection.count == groups.filter { $0.mode != .readOnly }.reduce(0) { $0 + $1.items.count })
    }

    // Solo Swift: `build` confina le voci KEEP in un gruppo in sola lettura, quindi il test sopra non
    // esercita il filtro finale di `selection`. Qui i gruppi sono costruiti a mano, con una voce KEEP
    // anche in un gruppo a blocco e in uno selezionabile, come potrebbe consegnarli un chiamante
    // sbagliato: la selezione deve comunque scartarla.
    @Test func selectionDropsKeptResourcesEvenFromHandBuiltGroups() {
        func candidate(_ id: String, _ verdict: DockerVerdict) -> DockerCandidate {
            DockerCandidate(kind: .volume, id: id, displayName: id, sizeBytes: 1, verdict: verdict, ruleId: "rule", reason: "r", cost: "c")
        }
        let blockDelete = candidate("block-delete", .delete)
        let blockKeep = candidate("block-keep", .keep)
        let selectableAsk = candidate("selectable-ask", .ask)
        let selectableKeep = candidate("selectable-keep", .keep)
        let groups = [
            DockerConfirmationGroup(id: "block", title: "t", description: "d", mode: .block, items: [blockKeep, blockDelete]),
            DockerConfirmationGroup(id: "selectable", title: "t", description: "d", mode: .selectable, items: [selectableKeep, selectableAsk]),
        ]

        let selection = DockerConfirmationGroups.selection(groups, isGroupSelected: { _ in true }, isItemSelected: { _ in true })

        #expect(selection == [blockDelete, selectableAsk])
    }

    @Test func blockGroupIsAllOrNothing() throws {
        let groups = try realCaseGroups()

        // Le righe di un blocco non si selezionano singolarmente: conta solo la casella del gruppo.
        let withBlock = DockerConfirmationGroups.selection(groups, isGroupSelected: { $0.mode == .block }, isItemSelected: { _ in false })
        let withoutBlock = DockerConfirmationGroups.selection(groups, isGroupSelected: { _ in false }, isItemSelected: { _ in false })

        #expect(withBlock.count == 4)
        #expect(withoutBlock.isEmpty)
    }
}
