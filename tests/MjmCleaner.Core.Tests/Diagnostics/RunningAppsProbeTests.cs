using MjmCleaner.Core.Diagnostics;

namespace MjmCleaner.Core.Tests.Diagnostics;

public class RunningAppsProbeTests
{
    private static RunningAppsProbe Create(params string[] processes)
        => new(() => processes);

    [Fact]
    public void MatchesBundleIdentifierAgainstProcessName()
    {
        IReadOnlyList<string> affected = Create("Safari", "Finder")
            .AffectedApps(["/Users/tester/Library/Caches/com.apple.Safari"]);

        Assert.Equal(["Safari"], affected);
    }

    [Fact]
    public void IgnoresProcessesNotInvolved()
    {
        IReadOnlyList<string> affected = Create("Mail")
            .AffectedApps(["/Users/tester/Library/Caches/com.apple.Safari"]);

        Assert.Empty(affected);
    }

    [Fact]
    public void ReportsEachApplicationOnlyOnce()
    {
        IReadOnlyList<string> affected = Create("Safari").AffectedApps(
        [
            "/Users/tester/Library/Caches/com.apple.Safari",
            "/Users/tester/Library/Caches/com.apple.Safari.WebKit",
        ]);

        Assert.Equal(["Safari"], affected);
    }

    [Fact]
    public void IgnoresVeryShortProcessNamesToAvoidFalsePositives()
    {
        IReadOnlyList<string> affected = Create("ls")
            .AffectedApps(["/Users/tester/Library/Caches/com.apple.Tools"]);

        Assert.Empty(affected);
    }

    // Confronto per parole intere, non per sottostringa: un nome di processo corrisponde solo
    // quando una sua parola (di almeno 4 caratteri) coincide con una parola del nome di cartella,
    // non quando è semplicemente contenuta al suo interno. Casi verificati a mano su dati reali:
    // "Dock" (4 caratteri, macOS Dock) non deve corrispondere a "com.docker.docker" né a
    // "Docker Desktop" solo perché "dock" è una sottostringa di "docker".
    [Theory]
    [InlineData("Safari", "/Users/tester/Library/Caches/com.apple.Safari", true)]
    [InlineData("Google Chrome", "/Users/tester/Library/Caches/com.google.Chrome", true)]
    [InlineData("Docker", "/Users/tester/Library/Caches/Docker Desktop", true)]
    [InlineData("Dock", "/Users/tester/Library/Caches/com.docker.docker", false)]
    [InlineData("Dock", "/Users/tester/Library/Caches/Docker Desktop", false)]
    public void MatchesWholeWordsNotSubstrings(string processName, string path, bool expectMatch)
    {
        IReadOnlyList<string> affected = Create(processName).AffectedApps([path]);

        if (expectMatch)
        {
            Assert.Equal([processName], affected);
        }
        else
        {
            Assert.Empty(affected);
        }
    }

    [Fact]
    public void SystemDaemonsDoNotMatchRealisticCacheFolders()
    {
        IReadOnlyList<string> affected = Create("accountsd", "secd", "tipsd").AffectedApps(
        [
            "/Users/tester/Library/Caches/com.apple.Safari",
            "/Users/tester/Library/Caches/com.google.Chrome",
            "/Users/tester/Library/Caches/JetBrains",
            "/Users/tester/Library/Caches/Homebrew",
            "/Users/tester/Library/Caches/Docker Desktop",
        ]);

        Assert.Empty(affected);
    }

    [Fact]
    public void ReportsFullProcessNameWhenOnlyOneWordMatches()
    {
        IReadOnlyList<string> affected = Create("Docker Desktop")
            .AffectedApps(["/Users/tester/Library/Caches/Docker"]);

        Assert.Equal(["Docker Desktop"], affected);
    }

    // --- ExtractApplicationNames: dal percorso completo del processo al nome dell'app -------
    //
    // Il vecchio elenco di parole generiche ("apple", "com", ...) è stato rimosso: serviva a
    // compensare il rumore prodotto dai demoni di sistema quando la sorgente dei nomi era
    // Process.ProcessName. Ora i demoni non entrano più nell'elenco dei candidati: vengono
    // scartati qui, in base al percorso, perché non hanno un bundle .app in un posto che
    // l'utente riconosce come "le mie applicazioni" — non perché condividono una parola con
    // il nome della cartella cache.

    [Theory]
    [InlineData("/Applications/Safari.app/Contents/MacOS/Safari", "Safari")]
    [InlineData("/System/Applications/Calendar.app/Contents/MacOS/Calendar", "Calendar")]
    public void ExtractApplicationNamesRecognizesSimpleBundlesInStandardLocations(string path, string expectedName)
    {
        IReadOnlyList<string> names = RunningAppsProbe.ExtractApplicationNames([path]);

        Assert.Equal([expectedName], names);
    }

    [Fact]
    public void ExtractApplicationNamesRecognizesBundlesUnderTheUserHomeDirectory()
    {
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        string path = $"{home}/Applications/HomeBrewedApp.app/Contents/MacOS/HomeBrewedApp";

        IReadOnlyList<string> names = RunningAppsProbe.ExtractApplicationNames([path]);

        Assert.Equal(["HomeBrewedApp"], names);
    }

    [Fact]
    public void ExtractApplicationNamesReturnsTheOutermostBundleNameForNestedHelperProcesses()
    {
        IReadOnlyList<string> names = RunningAppsProbe.ExtractApplicationNames(
        [
            "/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)",
        ]);

        Assert.Equal(["Claude"], names);
    }

    [Theory]
    [InlineData("/usr/libexec/secd")] // nessun bundle .app
    [InlineData("/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter")] // bundle, ma sotto /System/Library
    [InlineData("")] // percorso vuoto
    [InlineData("   ")] // percorso vuoto/malformato
    [InlineData("not a path at all")] // malformato, nessun bundle
    public void ExtractApplicationNamesDiscardsPathsOutsideUserFacingApplications(string path)
    {
        IReadOnlyList<string> names = RunningAppsProbe.ExtractApplicationNames([path]);

        Assert.Empty(names);
    }

    // Il caso che chiude il finding: demoni di sistema realistici, incluso uno che possiede un
    // bundle .app ma vive sotto /System/Library, non devono produrre alcuna segnalazione.
    [Fact]
    public void ExtractApplicationNamesIgnoresRealisticSystemDaemonPaths()
    {
        IReadOnlyList<string> names = RunningAppsProbe.ExtractApplicationNames(
        [
            "/usr/libexec/secd",
            "/System/Library/Frameworks/Accounts.framework/Versions/A/Support/accountsd",
            "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
        ]);

        Assert.Empty(names);
    }
}
