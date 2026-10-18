import Testing
@testable import CleanerCore

struct DenyListTests {
    private static let home = "/Users/tester"

    private func create() throws -> DenyList {
        try DenyList(homeDirectory: Self.home)
    }

    @Test(arguments: [
        "/System/Library/Fonts",
        "/usr/bin",
        "/bin",
        "/Applications/Safari.app",
        "/Users/tester",
        "/Users/tester/Documents",
        "/Users/tester/Documents/fatture/2026",
        "/Users/tester/Desktop",
        "/Users/tester/Library/Application Support/qualcosa",
        "/Users/tester/Library/Mobile Documents",
        "/Users/tester/.ssh/id_rsa",
        "/Users/tester/Library/Containers/com.docker.docker/Data",
    ])
    func deniesProtectedPaths(path: String) throws {
        #expect(try create().isDenied(path))
    }

    @Test(arguments: [
        "/Users/tester/Library/Caches/com.apple.Safari",
        "/Users/tester/Library/Logs/qualcosa.log",
        "/Library/Caches/com.apple.qualcosa",
        "/Library/Logs/DiagnosticReports/report.crash",
        "/Users/tester/.nuget/packages/newtonsoft.json",
        "/Users/tester/projects/app/bin",
    ])
    func allowsCleanablePaths(path: String) throws {
        #expect(try !create().isDenied(path))
    }

    @Test(arguments: [
        "/Users/tester/documents/fatture",
        "/Users/TESTER/Documents",
        "/users/tester/.SSH/config",
    ])
    func deniesRegardlessOfCase(path: String) throws {
        #expect(try create().isDenied(path))
    }

    @Test func deniesLibraryButAllowsItsCachesAndLogs() throws {
        let list = try create()
        #expect(list.isDenied("/Library/Preferences"))
        #expect(!list.isDenied("/Library/Caches/x"))
        #expect(!list.isDenied("/Library/Logs/x"))
    }

    @Test func reasonExplainsWhichRuleMatched() throws {
        let reason = try #require(try create().deniedReason("/Users/tester/Documents/x"))
        #expect(reason.contains("Documents"))
    }

    @Test(arguments: ["/", "//", "///", ""])
    func deniesRootInAllVariants(path: String) throws {
        #expect(try create().isDenied(path))
    }

    @Test(arguments: ["/Users", "/Users/altro-utente/Documents"])
    func deniesUsersDirectoryAndOtherUsersHomes(path: String) throws {
        #expect(try create().isDenied(path))
    }

    @Test(arguments: [
        "/Library/Caches/../Preferences",
        "/Library/Caches/../../etc/passwd",
        "/Library/Logs/../Keychains",
        "~//Documents",
        "~/./Documents",
    ])
    func deniesNonCanonicalPathsWithExplicitReason(path: String) throws {
        #expect(try create().deniedReason(path) == "percorso non canonico")
    }

    @Test(arguments: ["/Volumes/Backup", "/Volumes/Time Machine/x"])
    func deniesVolumes(path: String) throws {
        #expect(try create().isDenied(path))
    }

    @Test(arguments: [
        "/private/etc/hosts",
        "/private/var/db/something",
        "/private/var/root/.bash_history",
        "/Network/Servers",
        "/cores/core.123",
        "/opt/homebrew/bin/brew",
    ])
    func deniesAdditionalSystemPaths(path: String) throws {
        #expect(try create().isDenied(path))
    }

    @Test(arguments: [
        "/Users/tester/Library/Messages/chat.db",
        "/Users/tester/Library/Mail/V10",
        "/Users/tester/Library/Safari/Bookmarks.plist",
        "/Users/tester/Library/Preferences/com.apple.finder.plist",
        "/Users/tester/Library/Group Containers/group.com.apple.notes",
        "/Users/tester/Library/Application Scripts/com.apple.finder",
        "/Users/tester/Library/Containers/com.apple.mail",
        "/Users/tester/.aws/credentials",
        "/Users/tester/.kube/config",
        "/Users/tester/.docker/config.json",
        "/Users/tester/.config/gh/config.yml",
        "/Users/tester/.password-store/personal",
        "/Users/tester/.local/share/foo",
        "/Users/tester/Applications/Chrome.app",
        "/Users/tester/Public/Drop Box",
        "/Users/tester/Sites/index.html",
    ])
    func deniesNewHomeSubtrees(path: String) throws {
        #expect(try create().isDenied(path))
    }

    // IMPORTANT 3 della revisione del PathGuard: da macOS 12 OneDrive, Dropbox e Google Drive
    // montano qui i documenti dell'utente, e Xcode/UserData contiene identità di firma e
    // profili di provisioning. Proteggere iCloud (Mobile Documents) e non questi era
    // un'asimmetria arbitraria che costa dati.
    @Test(arguments: [
        "/Users/tester/Library/CloudStorage/OneDrive-Personal/report.docx",
        "/Users/tester/Library/Developer/Xcode/UserData/KeyBindings/Default.idekeybindings",
    ])
    func deniesNewlyAddedHomeSubtrees(path: String) throws {
        #expect(try create().isDenied(path))
    }

    // La voce aggiunta sopra è specifica a "Xcode/UserData": non deve intaccare DerivedData e
    // Archives, due categorie dell'app che devono restare pulibili.
    @Test(arguments: [
        "/Users/tester/Library/Developer/Xcode/DerivedData/App-abc123/Build",
        "/Users/tester/Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive",
    ])
    func keepsXcodeDerivedDataAndArchivesCleanable(path: String) throws {
        #expect(try !create().isDenied(path))
    }

    @Test func deniesDockerContainerWithSpecificReasonBeforeGenericContainers() throws {
        let reason = try #require(try create().deniedReason("/Users/tester/Library/Containers/com.docker.docker/Data"))
        #expect(reason.lowercased().contains("docker"))
    }

    @Test(arguments: [
        "/Users/tester/Library/Caches",
        "/Library/Caches",
        "/Users/tester/Library/Logs",
        "/Library/Logs",
        "/Users/tester/Library/Logs/DiagnosticReports",
        "/Users/tester/.Trash",
        "/Users/tester/Downloads",
        "/Users/tester/.nuget",
        "/Users/tester/.npm",
        "/Users/tester/.cache",
        "/Users/tester/Library/Developer",
        "/private/var/folders",
        "/tmp",
    ])
    func keepsAppCategoriesCleanable(path: String) throws {
        #expect(try !create().isDenied(path))
    }

    @Test(arguments: [nil, "", "   ", "relative/path", "/", "//", "///", "/Users"] as [String?])
    func constructorRejectsInvalidHomeDirectory(homeDirectory: String?) {
        #expect(throws: InvalidConfiguration.self) { try DenyList(homeDirectory: homeDirectory) }
    }

    // La proprietà di sicurezza che conta è questa, non solo "lancia un'eccezione": se una
    // forma degenere di homeDirectory riuscisse comunque a costruire una DenyList, quella
    // istanza non deve MAI rispondere IsDenied(".../Documents/x") == false. Oggi lo
    // garantiamo lanciando prima che l'istanza esista; se in futuro qualcuno intercettasse
    // l'eccezione altrove, questo test resterebbe comunque un'assicurazione contro una
    // deny-list permissiva.
    @Test(arguments: [nil, "", "   ", "relative/path", "/", "//", "///", "/Users"] as [String?])
    func degenerateHomeDirectoryNeverProducesADenyListThatAllowsProtectedPaths(homeDirectory: String?) {
        do {
            let list = try DenyList(homeDirectory: homeDirectory)
            #expect(list.isDenied("/Users/tester/Documents/x"))
        } catch {
            #expect(error is InvalidConfiguration)
        }
    }
}
