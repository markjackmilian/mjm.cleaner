using MjmCleaner.Core.Docker;

namespace MjmCleaner.Core.Tests.Docker;

public class DockerConfirmationGroupsTests
{
    private static IReadOnlyList<DockerConfirmationGroup> RealCaseGroups()
        => DockerConfirmationGroups.Build(DockerClassifier.Classify(DockerFixtures.Snapshot(), ProjectReferences.Empty));

    [Fact]
    public void GroupsFollowTheRiskOrderAndSkipEmptyOnes()
    {
        Assert.Equal(
            [DockerConfirmationGroups.SafeId, DockerConfirmationGroups.LocalBuildsId, DockerConfirmationGroups.UnusedImagesId, DockerConfirmationGroups.UnusedVolumesId, DockerConfirmationGroups.KeepId],
            RealCaseGroups().Select(g => g.Id));

        IReadOnlyList<DockerConfirmationGroup> onlyKeep = DockerConfirmationGroups.Build(
            [new DockerCandidate(DockerResourceKind.Image, "sha256:1", "a", 1, DockerVerdict.Keep, "in-use", "r", "c")]);
        Assert.Equal([DockerConfirmationGroups.KeepId], onlyKeep.Select(g => g.Id));
    }

    [Fact]
    public void SafeDeletionsAreConfirmedAsABlock()
    {
        DockerConfirmationGroup safe = RealCaseGroups().Single(g => g.Id == DockerConfirmationGroups.SafeId);

        Assert.Equal(DockerGroupMode.Block, safe.Mode);
        Assert.True(safe.SelectedByDefault);
        Assert.Equal(
            ["Cache di build", "dcptun_developer_ms:0.25.13", "mcr.microsoft.com/azurelinux/base/core:3.0", "testcontainers/ryuk:0.14.0"],
            safe.Items.Select(i => i.DisplayName).Order(StringComparer.Ordinal));
    }

    [Fact]
    public void ProposeAndAskGroupsStartUnselected()
    {
        Assert.All(
            RealCaseGroups().Where(g => g.Mode == DockerGroupMode.Selectable),
            group => Assert.False(group.SelectedByDefault));
    }

    [Fact]
    public void KeptResourcesAreReadOnly()
    {
        DockerConfirmationGroup keep = RealCaseGroups().Single(g => g.Id == DockerConfirmationGroups.KeepId);

        Assert.Equal(DockerGroupMode.ReadOnly, keep.Mode);
        Assert.All(keep.Items, i => Assert.Equal(DockerVerdict.Keep, i.Verdict));
    }

    [Fact]
    public void UnusedNamedVolumesNeedIndividualConfirmation()
    {
        DockerCandidate named = new(DockerResourceKind.Volume, "old", "old", 1, DockerVerdict.Propose, "named-unused", "r", "c");
        DockerCandidate anonymous = named with { Id = "anon", DisplayName = "anon", RuleId = "anonymous" };

        Assert.True(DockerConfirmationGroups.RequiresIndividualConfirmation(named));
        Assert.False(DockerConfirmationGroups.RequiresIndividualConfirmation(anonymous));
    }

    [Fact]
    public void SelectionNeverContainsKeptResources()
    {
        IReadOnlyList<DockerConfirmationGroup> groups = RealCaseGroups();
        HashSet<DockerCandidate> everything = [.. groups.SelectMany(g => g.Items)];

        IReadOnlyList<DockerCandidate> selection = DockerConfirmationGroups.Selection(groups, _ => true, everything.Contains);

        Assert.DoesNotContain(selection, c => c.Verdict == DockerVerdict.Keep);
        Assert.Equal(groups.Where(g => g.Mode != DockerGroupMode.ReadOnly).Sum(g => g.Items.Count), selection.Count);
    }

    [Fact]
    public void BlockGroupIsAllOrNothing()
    {
        IReadOnlyList<DockerConfirmationGroup> groups = RealCaseGroups();

        // Le righe di un blocco non si selezionano singolarmente: conta solo la casella del gruppo.
        IReadOnlyList<DockerCandidate> withBlock = DockerConfirmationGroups.Selection(groups, g => g.Mode == DockerGroupMode.Block, _ => false);
        IReadOnlyList<DockerCandidate> withoutBlock = DockerConfirmationGroups.Selection(groups, _ => false, _ => false);

        Assert.Equal(4, withBlock.Count);
        Assert.Empty(withoutBlock);
    }
}
