import Foundation

public struct CategorySelection: Sendable, Equatable {
    public let categoryId: String
    public let items: [ScanItem]

    public init(categoryId: String, items: [ScanItem]) {
        self.categoryId = categoryId
        self.items = items
    }
}

public struct CategoryCleanResult: Sendable, Equatable {
    public let categoryId: String
    public let bytesFreed: Int64
    public let itemsDeleted: Int

    public init(categoryId: String, bytesFreed: Int64, itemsDeleted: Int) {
        self.categoryId = categoryId
        self.bytesFreed = bytesFreed
        self.itemsDeleted = itemsDeleted
    }
}

public struct CleanProgress: Sendable, Equatable {
    public let currentPath: String
    public let itemsDone: Int
    public let itemsTotal: Int
    public let bytesFreed: Int64

    public init(currentPath: String, itemsDone: Int, itemsTotal: Int, bytesFreed: Int64) {
        self.currentPath = currentPath
        self.itemsDone = itemsDone
        self.itemsTotal = itemsTotal
        self.bytesFreed = bytesFreed
    }
}

public struct CleanReport: Sendable, Equatable {
    public let startedAt: Date
    public let duration: Duration
    public let bytesFreed: Int64
    public let itemsDeleted: Int
    public let itemsFailed: Int
    public let categories: [CategoryCleanResult]
    public let errors: [ScanError]
    public let deletedPaths: [String]

    public init(
        startedAt: Date,
        duration: Duration,
        bytesFreed: Int64,
        itemsDeleted: Int,
        itemsFailed: Int,
        categories: [CategoryCleanResult],
        errors: [ScanError],
        deletedPaths: [String]
    ) {
        self.startedAt = startedAt
        self.duration = duration
        self.bytesFreed = bytesFreed
        self.itemsDeleted = itemsDeleted
        self.itemsFailed = itemsFailed
        self.categories = categories
        self.errors = errors
        self.deletedPaths = deletedPaths
    }
}

/// Riceve ogni percorso nel momento in cui viene eliminato (spec §8.2, diario della pulizia).
public protocol DeletionRecording: Sendable {
    func recordDeleted(_ path: String)
}
