import Testing
@testable import CleanerCore

struct ScanEngineTests {
    private static let home = "/Users/tester"
    private static let now = utc(2026, 9, 15, 12)
    private static let all = ["*"]

    private func create(_ fs: InMemoryFileSystem) throws -> ScanEngine {
        let links = FakeLinkInspector()
        let scanner = RuleScanner(
            fileSystem: fs,
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: links, homeDirectory: Self.home),
            links: links,
            clock: FixedWallClock(now: Self.now))
        return ScanEngine(scanner: scanner)
    }

    private func category(_ id: String, _ rules: CleanupRule...) -> CleanupCategory {
        CleanupCategory(id: id, displayName: id, description: "", risk: .low, selectedByDefault: true, parentId: nil, rules: rules)
    }

    private func clearContents(_ root: String) -> CleanupRule {
        CleanupRule(root, .clearContents, include: Self.all, exclude: [])
    }

    @Test func aggregatesBytesPerCategory() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.home)/Library/Caches/a.tmp", size: 100)
        fs.addFile("\(Self.home)/Library/Caches/b.tmp", size: 50)

        let results = try await create(fs).scan([category("caches", clearContents("\(Self.home)/Library/Caches"))], progress: nil)

        let result = try #require(results.first)
        #expect(results.count == 1)
        #expect(result.categoryId == "caches")
        #expect(result.totalBytes == 150)
        #expect(result.items.count == 2)
    }

    @Test func mergesItemsFromAllRulesOfACategory() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.home)/Library/Caches/a.tmp", size: 10)
        fs.addFile("\(Self.home)/.cache/b.tmp", size: 20)

        let results = try await create(fs).scan(
            [category("misto", clearContents("\(Self.home)/Library/Caches"), clearContents("\(Self.home)/.cache"))],
            progress: nil)

        #expect(results.map(\.totalBytes) == [30])
    }

    @Test func returnsOneResultPerCategoryInInputOrder() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.home)/Library/Caches/a.tmp", size: 10)
        fs.addFile("\(Self.home)/.cache/b.tmp", size: 10)

        let results = try await create(fs).scan(
            [category("uno", clearContents("\(Self.home)/Library/Caches")), category("due", clearContents("\(Self.home)/.cache"))],
            progress: nil)

        #expect(results.map(\.categoryId) == ["uno", "due"])
    }

    @Test func reportsProgressForEachCategory() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.home)/Library/Caches/a.tmp", size: 10)
        let reported = Recorder<ScanProgress>()

        _ = try await create(fs).scan(
            [category("caches", clearContents("\(Self.home)/Library/Caches"))],
            progress: { reported.append($0) })

        #expect(reported.values.contains { $0.categoryId == "caches" })
    }

    @Test func cancellationPropagates() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.home)/Library/Caches/a.tmp", size: 10)
        let engine = try create(fs)
        let categories = [category("caches", clearContents("\(Self.home)/Library/Caches"))]

        let task = Task {
            cancelCurrentTask()
            return try await engine.scan(categories, progress: nil)
        }

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func categoryWithoutRulesYieldsEmptyResult() async throws {
        let results = try await create(InMemoryFileSystem()).scan([category("vuota")], progress: nil)

        let result = try #require(results.first)
        #expect(result.totalBytes == 0)
        #expect(result.items.isEmpty)
    }
}
