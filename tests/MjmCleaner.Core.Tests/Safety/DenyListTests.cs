using MjmCleaner.Core.Safety;

namespace MjmCleaner.Core.Tests.Safety;

public class DenyListTests
{
    private const string Home = "/Users/tester";
    private static DenyList Create() => new(Home);

    [Theory]
    [InlineData("/System/Library/Fonts")]
    [InlineData("/usr/bin")]
    [InlineData("/bin")]
    [InlineData("/Applications/Safari.app")]
    [InlineData("/Users/tester")]
    [InlineData("/Users/tester/Documents")]
    [InlineData("/Users/tester/Documents/fatture/2026")]
    [InlineData("/Users/tester/Desktop")]
    [InlineData("/Users/tester/Library/Application Support/qualcosa")]
    [InlineData("/Users/tester/Library/Mobile Documents")]
    [InlineData("/Users/tester/.ssh/id_rsa")]
    [InlineData("/Users/tester/Library/Containers/com.docker.docker/Data")]
    public void DeniesProtectedPaths(string path)
    {
        Assert.True(Create().IsDenied(path, out _));
    }

    [Theory]
    [InlineData("/Users/tester/Library/Caches/com.apple.Safari")]
    [InlineData("/Users/tester/Library/Logs/qualcosa.log")]
    [InlineData("/Library/Caches/com.apple.qualcosa")]
    [InlineData("/Library/Logs/DiagnosticReports/report.crash")]
    [InlineData("/Users/tester/.nuget/packages/newtonsoft.json")]
    [InlineData("/Users/tester/projects/app/bin")]
    public void AllowsCleanablePaths(string path)
    {
        Assert.False(Create().IsDenied(path, out _));
    }

    [Theory]
    [InlineData("/Users/tester/documents/fatture")]
    [InlineData("/Users/TESTER/Documents")]
    [InlineData("/users/tester/.SSH/config")]
    public void DeniesRegardlessOfCase(string path)
    {
        Assert.True(Create().IsDenied(path, out _));
    }

    [Fact]
    public void DeniesLibraryButAllowsItsCachesAndLogs()
    {
        DenyList list = Create();
        Assert.True(list.IsDenied("/Library/Preferences", out _));
        Assert.False(list.IsDenied("/Library/Caches/x", out _));
        Assert.False(list.IsDenied("/Library/Logs/x", out _));
    }

    [Fact]
    public void ReasonExplainsWhichRuleMatched()
    {
        Create().IsDenied("/Users/tester/Documents/x", out string reason);
        Assert.Contains("Documents", reason);
    }

    [Theory]
    [InlineData("/")]
    [InlineData("//")]
    [InlineData("///")]
    [InlineData("")]
    public void DeniesRootInAllVariants(string path)
    {
        Assert.True(Create().IsDenied(path, out _));
    }

    [Theory]
    [InlineData("/Users")]
    [InlineData("/Users/altro-utente/Documents")]
    public void DeniesUsersDirectoryAndOtherUsersHomes(string path)
    {
        Assert.True(Create().IsDenied(path, out _));
    }

    [Theory]
    [InlineData("/Library/Caches/../Preferences")]
    [InlineData("/Library/Caches/../../etc/passwd")]
    [InlineData("/Library/Logs/../Keychains")]
    [InlineData("~//Documents")]
    [InlineData("~/./Documents")]
    public void DeniesNonCanonicalPathsWithExplicitReason(string path)
    {
        bool denied = Create().IsDenied(path, out string reason);
        Assert.True(denied);
        Assert.Equal("percorso non canonico", reason);
    }

    [Theory]
    [InlineData("/Volumes/Backup")]
    [InlineData("/Volumes/Time Machine/x")]
    public void DeniesVolumes(string path)
    {
        Assert.True(Create().IsDenied(path, out _));
    }

    [Theory]
    [InlineData("/private/etc/hosts")]
    [InlineData("/private/var/db/something")]
    [InlineData("/private/var/root/.bash_history")]
    [InlineData("/Network/Servers")]
    [InlineData("/cores/core.123")]
    [InlineData("/opt/homebrew/bin/brew")]
    public void DeniesAdditionalSystemPaths(string path)
    {
        Assert.True(Create().IsDenied(path, out _));
    }

    [Theory]
    [InlineData("/Users/tester/Library/Messages/chat.db")]
    [InlineData("/Users/tester/Library/Mail/V10")]
    [InlineData("/Users/tester/Library/Safari/Bookmarks.plist")]
    [InlineData("/Users/tester/Library/Preferences/com.apple.finder.plist")]
    [InlineData("/Users/tester/Library/Group Containers/group.com.apple.notes")]
    [InlineData("/Users/tester/Library/Application Scripts/com.apple.finder")]
    [InlineData("/Users/tester/Library/Containers/com.apple.mail")]
    [InlineData("/Users/tester/.aws/credentials")]
    [InlineData("/Users/tester/.kube/config")]
    [InlineData("/Users/tester/.docker/config.json")]
    [InlineData("/Users/tester/.config/gh/config.yml")]
    [InlineData("/Users/tester/.password-store/personal")]
    [InlineData("/Users/tester/.local/share/foo")]
    [InlineData("/Users/tester/Applications/Chrome.app")]
    [InlineData("/Users/tester/Public/Drop Box")]
    [InlineData("/Users/tester/Sites/index.html")]
    public void DeniesNewHomeSubtrees(string path)
    {
        Assert.True(Create().IsDenied(path, out _));
    }

    // IMPORTANT 3 della revisione del PathGuard: da macOS 12 OneDrive, Dropbox e Google Drive
    // montano qui i documenti dell'utente, e Xcode/UserData contiene identità di firma e
    // profili di provisioning. Proteggere iCloud (Mobile Documents) e non questi era
    // un'asimmetria arbitraria che costa dati.
    [Theory]
    [InlineData("/Users/tester/Library/CloudStorage/OneDrive-Personal/report.docx")]
    [InlineData("/Users/tester/Library/Developer/Xcode/UserData/KeyBindings/Default.idekeybindings")]
    public void DeniesNewlyAddedHomeSubtrees(string path)
    {
        Assert.True(Create().IsDenied(path, out _));
    }

    // La voce aggiunta sopra è specifica a "Xcode/UserData": non deve intaccare DerivedData e
    // Archives, due categorie dell'app che devono restare pulibili.
    [Theory]
    [InlineData("/Users/tester/Library/Developer/Xcode/DerivedData/App-abc123/Build")]
    [InlineData("/Users/tester/Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive")]
    public void KeepsXcodeDerivedDataAndArchivesCleanable(string path)
    {
        Assert.False(Create().IsDenied(path, out _));
    }

    [Fact]
    public void DeniesDockerContainerWithSpecificReasonBeforeGenericContainers()
    {
        Create().IsDenied("/Users/tester/Library/Containers/com.docker.docker/Data", out string reason);
        Assert.Contains("docker", reason, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData("/Users/tester/Library/Caches")]
    [InlineData("/Library/Caches")]
    [InlineData("/Users/tester/Library/Logs")]
    [InlineData("/Library/Logs")]
    [InlineData("/Users/tester/Library/Logs/DiagnosticReports")]
    [InlineData("/Users/tester/.Trash")]
    [InlineData("/Users/tester/Downloads")]
    [InlineData("/Users/tester/.nuget")]
    [InlineData("/Users/tester/.npm")]
    [InlineData("/Users/tester/.cache")]
    [InlineData("/Users/tester/Library/Developer")]
    [InlineData("/private/var/folders")]
    [InlineData("/tmp")]
    public void KeepsAppCategoriesCleanable(string path)
    {
        Assert.False(Create().IsDenied(path, out _));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("relative/path")]
    [InlineData("/")]
    [InlineData("//")]
    [InlineData("///")]
    [InlineData("/Users")]
    public void ConstructorRejectsInvalidHomeDirectory(string? homeDirectory)
    {
        Assert.Throws<ArgumentException>(() => new DenyList(homeDirectory));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("relative/path")]
    [InlineData("/")]
    [InlineData("//")]
    [InlineData("///")]
    [InlineData("/Users")]
    public void DegenerateHomeDirectoryNeverProducesADenyListThatAllowsProtectedPaths(string? homeDirectory)
    {
        DenyList? list = null;
        Exception? exception = Record.Exception(() => list = new DenyList(homeDirectory));

        // La proprietà di sicurezza che conta è questa, non solo "lancia un'eccezione": se una
        // forma degenere di homeDirectory riuscisse comunque a costruire una DenyList, quella
        // istanza non deve MAI rispondere IsDenied(".../Documents/x") == false. Oggi lo
        // garantiamo lanciando prima che l'istanza esista; se in futuro qualcuno intercettasse
        // l'eccezione altrove, questo test resterebbe comunque un'assicurazione contro una
        // deny-list permissiva.
        if (exception is null)
        {
            Assert.True(list!.IsDenied("/Users/tester/Documents/x", out _));
        }
        else
        {
            Assert.IsType<ArgumentException>(exception);
        }
    }
}
