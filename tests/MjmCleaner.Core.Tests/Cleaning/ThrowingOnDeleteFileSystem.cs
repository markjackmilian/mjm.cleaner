using System.IO.Abstractions;
using System.Reflection;

namespace MjmCleaner.Core.Tests.Cleaning;

/// <summary>
/// Decora un <see cref="IFileSystem"/> in modo che <c>File.Delete</c> su un percorso specifico
/// lanci un'eccezione FUORI dal contratto di <c>RuleScanner.IsExpected</c> (non
/// <see cref="UnauthorizedAccessException"/> né <see cref="IOException"/>): simula un errore
/// imprevisto — non uno dei casi noti (accesso negato, in uso, scomparso) — durante la
/// cancellazione, per verificare che <c>CleanEngine</c> restituisca comunque il resoconto
/// parziale invece di propagare e perdere la traccia di ciò già eliminato. Stessa forma dei
/// doppi in <c>Scanning/VanishingFileSystem.cs</c>, ridotta al minimo che serve qui: un solo
/// membro intercettato.
/// </summary>
internal sealed class ThrowingOnDeleteFileSystem(IFileSystem inner, string throwingPath) : IFileSystem
{
    public IDirectory Directory => inner.Directory;

    public IDirectoryInfoFactory DirectoryInfo => inner.DirectoryInfo;

    public IDriveInfoFactory DriveInfo => inner.DriveInfo;

    public IFile File { get; } = ThrowingFileProxy.Wrap(inner.File, throwingPath);

    public IFileInfoFactory FileInfo => inner.FileInfo;

    public IFileStreamFactory FileStream => inner.FileStream;

    public IFileSystemWatcherFactory FileSystemWatcher => inner.FileSystemWatcher;

    public IFileVersionInfoFactory FileVersionInfo => inner.FileVersionInfo;

    public IPath Path => inner.Path;
}

/// <summary>
/// Proxy dinamico su <see cref="IFile"/>: inoltra ogni membro all'istanza reale, tranne
/// <c>Delete(throwingPath)</c>, che lancia <see cref="InvalidOperationException"/>.
/// </summary>
internal class ThrowingFileProxy : DispatchProxy
{
    private IFile _inner = null!;
    private string _path = null!;

    protected override object? Invoke(MethodInfo? targetMethod, object?[]? args)
    {
        if (targetMethod!.Name == nameof(IFile.Delete)
            && args is [string path]
            && path == _path)
        {
            throw new InvalidOperationException($"errore imprevisto durante la cancellazione di {path}");
        }

        try
        {
            return targetMethod.Invoke(_inner, args);
        }
        catch (TargetInvocationException ex) when (ex.InnerException is not null)
        {
            throw ex.InnerException;
        }
    }

    public static IFile Wrap(IFile inner, string path)
    {
        object proxy = Create<IFile, ThrowingFileProxy>()!;
        ThrowingFileProxy target = (ThrowingFileProxy)proxy;
        target._inner = inner;
        target._path = path;
        return (IFile)proxy;
    }
}
