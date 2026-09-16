using System.IO.Abstractions;
using System.Reflection;

namespace MjmCleaner.Core.Tests.Scanning;

/// <summary>
/// Decora un <see cref="IFileSystem"/> in modo che, la prima volta che <c>Directory.Exists</c>
/// restituisce true per un percorso specifico, quel percorso venga immediatamente eliminato (in
/// modo ricorsivo) dal filesystem simulato sottostante — simulando una directory che scompare
/// fra il momento in cui uno scanner la riconosce come tale e il momento in cui ne legge le
/// statistiche (dimensione, età). Riproduce fedelmente il comportamento reale: su una directory
/// scomparsa, <c>DirectoryInfo.LastWriteTimeUtc</c>/<c>LastAccessTimeUtc</c> non lanciano e
/// restituiscono la sentinella 1601-01-01, mentre <c>EnumerateFileSystemEntries</c> lancia
/// <see cref="DirectoryNotFoundException"/> — verificato empiricamente su
/// <c>MockFileSystem</c> prima di scrivere questo doppio.
/// </summary>
internal sealed class VanishingChildFileSystem(IFileSystem inner, string vanishingPath) : IFileSystem
{
    public IDirectory Directory { get; } = VanishingChildDirectoryProxy.Wrap(inner.Directory, vanishingPath);

    public IDirectoryInfoFactory DirectoryInfo => inner.DirectoryInfo;

    public IDriveInfoFactory DriveInfo => inner.DriveInfo;

    public IFile File => inner.File;

    public IFileInfoFactory FileInfo => inner.FileInfo;

    public IFileStreamFactory FileStream => inner.FileStream;

    public IFileSystemWatcherFactory FileSystemWatcher => inner.FileSystemWatcher;

    public IFileVersionInfoFactory FileVersionInfo => inner.FileVersionInfo;

    public IPath Path => inner.Path;
}

/// <summary>
/// Proxy dinamico su <see cref="IDirectory"/>: inoltra ogni membro all'istanza reale, tranne la
/// prima chiamata a <c>Exists(vanishingPath)</c> che restituisce true, dopo la quale elimina
/// quel percorso prima di restituire il risultato originale. Usa <see cref="DispatchProxy"/>
/// invece di implementare a mano tutti i membri di <c>IDirectory</c> che il codice sotto test
/// non chiama comunque per questo scenario.
/// </summary>
internal class VanishingChildDirectoryProxy : DispatchProxy
{
    private IDirectory _inner = null!;
    private string _target = null!;
    private bool _triggered;

    protected override object? Invoke(MethodInfo? targetMethod, object?[]? args)
    {
        if (!_triggered
            && targetMethod!.Name == nameof(IDirectory.Exists)
            && args is { Length: 1 } && args[0] is string path
            && path == _target)
        {
            bool existed = (bool)targetMethod.Invoke(_inner, args)!;
            if (existed)
            {
                _triggered = true;
                _inner.Delete(_target, recursive: true);
            }

            return existed;
        }

        try
        {
            return targetMethod!.Invoke(_inner, args);
        }
        catch (TargetInvocationException ex) when (ex.InnerException is not null)
        {
            throw ex.InnerException;
        }
    }

    public static IDirectory Wrap(IDirectory inner, string target)
    {
        object proxy = Create<IDirectory, VanishingChildDirectoryProxy>()!;
        VanishingChildDirectoryProxy typed = (VanishingChildDirectoryProxy)proxy;
        typed._inner = inner;
        typed._target = target;
        return (IDirectory)proxy;
    }
}
