public protocol ScanPerforming: Sendable {
    func scan(
        _ categories: [CleanupCategory],
        progress: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> [CategoryScanResult]
}

/// Scansiona le categorie in parallelo: attraversare ~/Library/Caches significa centinaia di
/// migliaia di file e l'interfaccia deve restare reattiva. `@concurrent` garantisce che il lavoro
/// non giri mai sul main actor del chiamante.
public struct ScanEngine: ScanPerforming {
    private let scanner: RuleScanner

    public init(scanner: RuleScanner) {
        self.scanner = scanner
    }

    @concurrent
    public func scan(
        _ categories: [CleanupCategory],
        progress: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> [CategoryScanResult] {
        try Task.checkCancellation()

        return try await withThrowingTaskGroup(of: (Int, CategoryScanResult).self) { group in
            for (index, category) in categories.enumerated() {
                group.addTask {
                    let result = try scanCategory(category, progress)
                    return (index, result)
                }
            }

            var collected: [(Int, CategoryScanResult)] = []
            for try await result in group {
                collected.append(result)
            }
            // L'ordine dei risultati è quello delle categorie in ingresso, come Task.WhenAll in C#.
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func scanCategory(
        _ category: CleanupCategory,
        _ progress: (@Sendable (ScanProgress) -> Void)?
    ) throws -> CategoryScanResult {
        var items: [ScanItem] = []
        var errors: [ScanError] = []
        var exclusions: [GuardExclusion] = []

        for rule in category.rules {
            try Task.checkCancellation()

            let outcome = try scanner.scan(rule)
            items += outcome.items
            errors += outcome.errors
            exclusions += outcome.exclusions

            progress?(ScanProgress(
                categoryId: category.id,
                currentPath: rule.root,
                itemsFound: items.count,
                bytesFound: items.reduce(0) { $0 + $1.sizeBytes }))
        }

        let total = items.reduce(0) { $0 + $1.sizeBytes }
        progress?(ScanProgress(categoryId: category.id, currentPath: "", itemsFound: items.count, bytesFound: total))

        return CategoryScanResult(categoryId: category.id, items: items, totalBytes: total, errors: errors, exclusions: exclusions)
    }
}
