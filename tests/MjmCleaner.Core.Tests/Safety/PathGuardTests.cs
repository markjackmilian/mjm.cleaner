using MjmCleaner.Core.Safety;

namespace MjmCleaner.Core.Tests.Safety;

public class PathGuardTests
{
    private const string Home = "/Users/tester";
    private const string CacheRoot = "/Users/tester/Library/Caches";

    private static PathGuard Create(params string[] symlinks)
        => new(new DenyList(Home), new FakeLinkInspector(symlinks), Home);

    [Fact]
    public void AllowsItemInsideDeclaredRoot()
    {
        GuardVerdict verdict = Create().Validate($"{CacheRoot}/com.apple.Safari", CacheRoot);
        Assert.True(verdict.IsAllowed);
    }

    [Fact]
    public void DeniesItemOutsideDeclaredRoot()
    {
        GuardVerdict verdict = Create().Validate("/Users/tester/projects/app/bin", CacheRoot);
        Assert.False(verdict.IsAllowed);
        Assert.Contains("contenimento", verdict.Reason);
    }

    [Fact]
    public void DeniesTraversalEscapingDeclaredRoot()
    {
        GuardVerdict verdict = Create().Validate($"{CacheRoot}/../../Documents/fatture", CacheRoot);
        Assert.False(verdict.IsAllowed);
    }

    // Sostituisce il test del brief "CanonicalizesBeforeComparing", che si aspettava questo
    // stesso input PERMESSO dopo una risoluzione testuale di "." e "..". Quella risoluzione è
    // il difetto misurato dalla revisione (CRITICAL 2): Path.GetFullPath risolve ".." prima di
    // seguire un eventuale collegamento simbolico, mentre il kernel lo risolve dopo — quindi un
    // percorso come "{root}/collegamento/.." veniva canonicalizzato a "{root}" (dentro la root,
    // permesso) mentre il sistema avrebbe cancellato il bersaglio del collegamento, altrove.
    // Nessuna canonicalizzazione testuale può chiudere questo buco: la correzione è rifiutare
    // ogni percorso con un segmento "." o ".." invece di risolverlo. Decisione presa in sede di
    // revisione, non un'interpretazione: qui si applica, non si discute più.
    [Fact]
    public void DeniesNonCanonicalPathWithDotSegments()
    {
        GuardVerdict verdict = Create().Validate($"{CacheRoot}/./sub/../sub/file", CacheRoot);
        Assert.False(verdict.IsAllowed);
    }

    [Fact]
    public void DeniesDeniedPathEvenWhenInsideDeclaredRoot()
    {
        GuardVerdict verdict = Create().Validate($"{Home}/Documents/x", Home);
        Assert.False(verdict.IsAllowed);
    }

    [Fact]
    public void DeniesHomeItself()
    {
        Assert.False(Create().Validate(Home, Home).IsAllowed);
    }

    [Fact]
    public void DeniesDirectChildOfHome()
    {
        GuardVerdict verdict = Create().Validate($"{Home}/Downloads", $"{Home}/Downloads");
        Assert.False(verdict.IsAllowed);
        Assert.Contains("profondità", verdict.Reason);
    }

    [Fact]
    public void AllowsGrandchildOfHome()
    {
        Assert.True(Create().Validate($"{Home}/Downloads/vecchio.dmg", $"{Home}/Downloads").IsAllowed);
    }

    [Fact]
    public void AllowsSymlinkItselfSoTheLinkCanBeRemoved()
    {
        PathGuard guard = Create($"{CacheRoot}/collegamento");
        Assert.True(guard.Validate($"{CacheRoot}/collegamento", CacheRoot).IsAllowed);
    }

    [Fact]
    public void DeniesItemWhoseAncestorIsSymlink()
    {
        PathGuard guard = Create($"{CacheRoot}/collegamento");
        GuardVerdict verdict = guard.Validate($"{CacheRoot}/collegamento/vittima.txt", CacheRoot);
        Assert.False(verdict.IsAllowed);
        Assert.Contains("collegamento", verdict.Reason);
    }

    // Il collegamento non è solo il genitore immediato: qualunque antenato fra l'elemento e la
    // root rompe il contenimento allo stesso modo. La revisione ha misurato che oggi
    // funzionano già — questi test li fissano perché non regrediscano con le correzioni.
    [Fact]
    public void DeniesItemTwoLevelsBelowSymlinkedAncestor()
    {
        PathGuard guard = Create($"{CacheRoot}/collegamento");
        GuardVerdict verdict = guard.Validate($"{CacheRoot}/collegamento/sub/vittima.txt", CacheRoot);
        Assert.False(verdict.IsAllowed);
    }

    [Fact]
    public void DeniesItemThreeLevelsBelowSymlinkedAncestor()
    {
        PathGuard guard = Create($"{CacheRoot}/collegamento");
        GuardVerdict verdict = guard.Validate($"{CacheRoot}/collegamento/sub/sub2/vittima.txt", CacheRoot);
        Assert.False(verdict.IsAllowed);
    }

    [Fact]
    public void DeniesRegardlessOfCase()
    {
        Assert.False(Create().Validate($"{Home}/documents/x", Home).IsAllowed);
    }

    [Fact]
    public void DeniesDockerContainer()
    {
        string docker = $"{Home}/Library/Containers/com.docker.docker/Data/vms";
        Assert.False(Create().Validate(docker, $"{Home}/Library/Containers").IsAllowed);
    }

    // I tre casi seguenti nascono dalla revisione del Task 3, che li aveva misurati
    // come passanti: la radice si riduceva a stringa vuota e sfuggiva a ogni confronto.
    [Theory]
    [InlineData("/")]
    [InlineData("//")]
    public void DeniesFilesystemRoot(string root)
    {
        Assert.False(Create().Validate(root, "/").IsAllowed);
    }

    [Fact]
    public void DeniesAnotherUsersHome()
    {
        Assert.False(Create().Validate("/Users/altro/Documents/fatture", "/Users").IsAllowed);
    }

    [Fact]
    public void DeniesExternalVolume()
    {
        Assert.False(Create().Validate("/Volumes/Backup/2026", "/Volumes").IsAllowed);
    }

    // CRITICAL 3 della revisione: con radice "/" o "//" il contenimento (path.StartsWith(root))
    // diventa vero per qualunque percorso assoluto, non solo per la radice stessa passata come
    // candidatePath (già coperto da DeniesFilesystemRoot). Qui il candidato è un percorso
    // normale, per misurare esattamente la fuga di contenimento segnalata.
    [Theory]
    [InlineData("/")]
    [InlineData("//")]
    public void DeniesAnyPathWhenDeclaredRootIsDegenerate(string root)
    {
        Assert.False(Create().Validate("/Users/tester/projects/app/bin", root).IsAllowed);
    }

    // CRITICAL 2(a): un segmento ".." dopo un nome che potrebbe essere un collegamento va
    // rifiutato per non canonicità, senza tentare di risolverlo — è esattamente il caso che
    // Path.GetFullPath risolveva testualmente facendo sparire il collegamento dalla stringa.
    [Theory]
    [InlineData("collegamento/..")]
    [InlineData("collegamento/../sub/file")]
    [InlineData("a/collegamento/../altro/x")]
    public void DeniesNonCanonicalPathThroughAlias(string suffix)
    {
        PathGuard guard = Create($"{CacheRoot}/collegamento");
        GuardVerdict verdict = guard.Validate($"{CacheRoot}/{suffix}", CacheRoot);
        Assert.False(verdict.IsAllowed);
    }

    // IMPORTANT 1: l'ultimo controllo prima di una cancellazione irreversibile deve restituire
    // un rifiuto anche su input malformati, mai un'eccezione che un catch a monte potrebbe
    // trasformare in un salto silenzioso.
    [Fact]
    public void DeniesEmptyCandidatePathWithoutThrowing()
    {
        GuardVerdict verdict = Create().Validate(string.Empty, CacheRoot);
        Assert.False(verdict.IsAllowed);
    }

    [Fact]
    public void DeniesEmptyDeclaredRootWithoutThrowing()
    {
        GuardVerdict verdict = Create().Validate($"{CacheRoot}/file", string.Empty);
        Assert.False(verdict.IsAllowed);
    }

    [Fact]
    public void DeniesPathWithEmbeddedNulCharacterWithoutThrowing()
    {
        GuardVerdict verdict = Create().Validate($"{CacheRoot}/file\0name", CacheRoot);
        Assert.False(verdict.IsAllowed);
    }

    // CRITICAL 1: la root dichiarata va verificata a parte, una volta per regola, risalendo
    // fino alla radice del filesystem — non solo fino alla root, come fa Validate per ciascun
    // elemento. Senza ValidateRoot, una root che sia essa stessa (o abbia come antenato) un
    // collegamento simbolico — es. una cache spostata su un disco esterno con
    // "ln -s /Volumes/SSD/Caches ~/Library/Caches" — non verrebbe mai esaminata.
    [Fact]
    public void ValidateRootAllowsOrdinaryRoot()
    {
        Assert.True(Create().ValidateRoot(CacheRoot).IsAllowed);
    }

    [Fact]
    public void ValidateRootDeniesWhenRootIsSymlink()
    {
        PathGuard guard = Create(CacheRoot);
        GuardVerdict verdict = guard.ValidateRoot(CacheRoot);
        Assert.False(verdict.IsAllowed);
        Assert.Contains("collegamento", verdict.Reason);
    }

    [Fact]
    public void ValidateRootDeniesWhenAncestorOfRootIsSymlink()
    {
        PathGuard guard = Create($"{Home}/Library");
        Assert.False(guard.ValidateRoot(CacheRoot).IsAllowed);
    }

    [Fact]
    public void ValidateRootDeniesWhenHomeIsSymlink()
    {
        PathGuard guard = Create(Home);
        Assert.False(guard.ValidateRoot(CacheRoot).IsAllowed);
    }

    // Dimostra perché ValidateRoot va invocata prima della scansione: il ciclo di Validate è
    // delimitato alla root (per non risalire alla radice del filesystem per ciascuno dei
    // centinaia di migliaia di elementi scansionati), quindi da solo non vede una root che sia
    // essa stessa un collegamento. Non è una regressione: è la responsabilità che ValidateRoot
    // esiste apposta per coprire.
    [Fact]
    public void ValidateAloneAllowsDirectChildOfSymlinkedRootButValidateRootDenies()
    {
        PathGuard guard = Create(CacheRoot);

        Assert.True(guard.Validate($"{CacheRoot}/child.tmp", CacheRoot).IsAllowed);
        Assert.False(guard.ValidateRoot(CacheRoot).IsAllowed);
    }

    // IMPORTANT 2: home e collegamento con la deny-list.
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("relative/path")]
    [InlineData("/")]
    [InlineData("//")]
    public void ConstructorRejectsInvalidHomeDirectory(string? homeDirectory)
    {
        Assert.Throws<ArgumentException>(
            () => new PathGuard(new DenyList(Home), new FakeLinkInspector(), homeDirectory));
    }

    [Fact]
    public void ConstructorRejectsHomeThatDiffersFromDenyListHome()
    {
        Assert.Throws<ArgumentException>(
            () => new PathGuard(new DenyList("/Users/altro"), new FakeLinkInspector(), Home));
    }
}
