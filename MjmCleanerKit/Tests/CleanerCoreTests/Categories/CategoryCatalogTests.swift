import Testing
@testable import CleanerCore

struct CategoryCatalogTests {
    private func build(_ settings: CleanerSettings = CleanerSettings()) throws -> [CleanupCategory] {
        CategoryCatalog.build(settings, try PathExpander(homeDirectory: "/Users/tester", tempDirectory: "/var/folders/ab/T"))
    }

    private func category(_ id: String, in categories: [CleanupCategory]) throws -> CleanupCategory {
        let matches = categories.filter { $0.id == id }
        #expect(matches.count == 1)
        return try #require(matches.first)
    }

    @Test func definesTheSevenCategories() throws {
        #expect(try build().map(\.id) == [
            "system-caches", "dev-caches", "nuget-packages", "project-build-output", "logs", "trash", "downloads-large",
        ])
    }

    @Test func nuGetIsNestedUnderDevCachesAndNotSelectedByDefault() throws {
        let nuget = try category("nuget-packages", in: build())
        #expect(nuget.parentId == "dev-caches")
        #expect(!nuget.selectedByDefault)
    }

    @Test func highRiskCategoryIsNeverSelectedByDefault() throws {
        let risky = try category("trash", in: build())
        #expect(risky.risk == .high)
        #expect(!risky.selectedByDefault)
    }

    @Test func ruleRootsAreAlreadyExpanded() throws {
        let caches = try category("system-caches", in: build())
        #expect(caches.rules.contains { $0.root == "/Users/tester/Library/Caches" })
        #expect(caches.rules.contains { $0.root == "/Library/Caches" })
        #expect(!caches.rules.contains { $0.root.hasPrefix("~") })
    }

    @Test func projectBuildOutputHasOneRulePerConfiguredRoot() throws {
        var settings = CleanerSettings()
        settings.projectRoots = ["/Users/tester/projects", "/Users/tester/lavoro"]

        let projects = try category("project-build-output", in: build(settings))

        #expect(projects.rules.count == 2)
        #expect(projects.rules.allSatisfy { $0.requiresProjectMarker })
        #expect(projects.rules.allSatisfy { $0.mode == .matchingDirs })
        #expect(projects.rules.allSatisfy { $0.includeGlobs == ["bin", "obj"] })
    }

    @Test func projectBuildOutputHasNoRulesWhenNoRootConfigured() throws {
        #expect(try category("project-build-output", in: build()).rules.isEmpty)
    }

    @Test func ageThresholdsComeFromSettings() throws {
        var settings = CleanerSettings()
        settings.logsMinAgeDays = 7
        settings.downloadsMinAgeDays = 45
        settings.nuGetMinAgeDays = 60
        let categories = try build(settings)

        let logRule = try #require(try category("logs", in: categories).rules.first)
        let downloadsRule = try #require(try category("downloads-large", in: categories).rules.first { $0.root == "/Users/tester/Downloads" })
        let nugetRule = try #require(try category("nuget-packages", in: categories).rules.first)

        #expect(logRule.minAge == days(7))
        #expect(downloadsRule.minAge == days(45))
        #expect(nugetRule.minAge == days(60))
    }

    @Test func dockerIsNotReferencedByAnyRule() throws {
        #expect(!(try build()).flatMap(\.rules).contains { $0.root.lowercased().contains("docker") })
    }

    @Test func generalDevelopmentCacheCategoryDoesNotContainDerivedData() throws {
        let development = try category("dev-caches", in: build())
        #expect(!development.rules.contains { $0.root.lowercased().contains("deriveddata") })
        #expect(development.description.lowercased().contains("pagina xcode"))
    }
}
