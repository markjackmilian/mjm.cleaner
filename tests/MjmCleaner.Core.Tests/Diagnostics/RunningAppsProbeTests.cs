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

    // "apple" (e altre parole generiche come "com") compare in moltissime cartelle cache Apple
    // e in moltissimi nomi di demoni di sistema, entrambi in stile reverse-DNS: senza esclusione
    // produrrebbe segnalazioni su larga scala e prive di significato (misurato sui dati reali:
    // 85% delle segnalazioni derivava dalla sola parola "apple" condivisa). Con l'esclusione,
    // demoni Apple realistici non devono corrispondere a cartelle cache Apple realistiche.
    [Fact]
    public void GenericReverseDnsWordsDoNotCauseAppleDaemonsToMatchAppleCacheFolders()
    {
        IReadOnlyList<string> affected = Create("com.apple.accountsd", "com.apple.secd", "com.apple.tipsd")
            .AffectedApps(
            [
                "/Users/tester/Library/Caches/com.apple.Safari",
                "/Users/tester/Library/Caches/com.apple.Dock",
                "/Users/tester/Library/Caches/com.apple.Mail",
                "/Users/tester/Library/Caches/com.apple.WebKit",
            ]);

        Assert.Empty(affected);
    }
}
