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

    @Test func definesTheEightCategories() throws {
        #expect(try build().map(\.id) == [
            "system-caches", "dev-caches", "nuget-packages", "project-build-output", "logs", "trash", "downloads", "large-files",
        ])
    }

    /// Solo «Cartelle bin e obj nei progetti» e «File grandi» prendono le regole dalle cartelle delle
    /// Impostazioni: senza cartelle restano vuote, e il passo 1 le mostra non disponibili (spec
    /// `2026-10-20-package-exclusions-folder-warning-design.md`). Ogni altra categoria ha sempre regole.
    @Test func onlyTheCategoriesFedBySettingsFoldersCanBeEmpty() throws {
        #expect(try build().filter(\.rules.isEmpty).map(\.id) == ["project-build-output", "large-files"])

        var settings = CleanerSettings()
        settings.projectRoots = ["~/src"]
        settings.largeFileRoots = ["~/Downloads"]
        #expect(try build(settings).filter(\.rules.isEmpty).isEmpty)
    }

    /// Download e file grandi contengono dati reali: mai preselezionati, né al passo 1 né al passo 3.
    @Test func downloadsAndLargeFilesAreHighRiskAndTheirItemsStartDeselected() throws {
        let categories = try build()
        for id in ["downloads", "large-files"] {
            let category = try category(id, in: categories)
            #expect(category.risk == .high)
            #expect(!category.selectedByDefault)
        }
        #expect(categories.filter { !$0.itemsSelectedByDefault }.map(\.id) == ["downloads", "large-files"])
    }

    @Test func downloadsHaveTheAgeRuleAndLargeFilesOneThresholdRulePerRoot() throws {
        var settings = CleanerSettings()
        settings.largeFileRoots = ["~/Lavoro", "/Volumes/Dati"]
        settings.largeFileThresholdBytes = 700 * 1_048_576
        settings.downloadsMinAgeDays = 45
        let categories = try build(settings)

        #expect(try category("downloads", in: categories).rules == [
            CleanupRule("/Users/tester/Downloads", .matchingFiles, include: ["*"], exclude: [], minAge: days(45)),
        ])
        #expect(try category("large-files", in: categories).rules == [
            CleanupRule("/Users/tester/Lavoro", .matchingFiles, include: ["*"], exclude: [], minSizeBytes: 700 * 1_048_576),
            CleanupRule("/Volumes/Dati", .matchingFiles, include: ["*"], exclude: [], minSizeBytes: 700 * 1_048_576),
        ])
    }

    @Test func excludedFoldersReachEveryRuleAlreadyExpanded() throws {
        var settings = CleanerSettings()
        settings.projectRoots = ["~/src"]
        settings.largeFileRoots = ["~"]
        settings.excludedFolders = ["~/Parallels", "/Volumes/Archivio/"]
        let rules = try build(settings).flatMap(\.rules)

        #expect(rules.count == 13)
        #expect(rules.allSatisfy { $0.excludedPaths == ["/Users/tester/Parallels", "/Volumes/Archivio"] })
    }

    /// `excluding` cambia solo le cartelle escluse: ogni altro campo della regola e della categoria
    /// resta com'era (la soglia di età di NuGet, la profondità, il marcatore di progetto…).
    @Test func excludingKeepsEveryOtherField() {
        let rule = CleanupRule(
            "/Users/tester/.nuget/packages", .matchingDirs, include: ["a*"], exclude: ["b*"], minAge: days(3), minSizeBytes: 7,
            maxDepth: 1, requiresProjectMarker: true)
        let category = CleanupCategory(
            id: "x", displayName: "X", description: "d", risk: .high, selectedByDefault: true, parentId: "p", rules: [rule],
            itemsSelectedByDefault: false)

        #expect(rule.excluding(["/e"]) == CleanupRule(
            "/Users/tester/.nuget/packages", .matchingDirs, include: ["a*"], exclude: ["b*"], minAge: days(3), minSizeBytes: 7,
            maxDepth: 1, requiresProjectMarker: true, excludedPaths: ["/e"]))
        #expect(category.excluding(["/e"]) == CleanupCategory(
            id: "x", displayName: "X", description: "d", risk: .high, selectedByDefault: true, parentId: "p",
            rules: [rule.excluding(["/e"])], itemsSelectedByDefault: false))
    }

    @Test func withoutExcludedFoldersNoRuleExcludesAnything() throws {
        #expect(try build().flatMap(\.rules).allSatisfy { $0.excludedPaths.isEmpty })
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
        let downloadsRule = try #require(try category("downloads", in: categories).rules.first)
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
