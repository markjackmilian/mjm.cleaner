using System.IO.Abstractions;
using System.Reflection;

namespace MjmCleaner.Core.Tests.Scanning;

/// <summary>
/// Decora un <see cref="IFileSystem"/> in modo che <c>Directory.EnumerateFileSystemEntries</c>
/// su un percorso specifico lanci sempre <see cref="UnauthorizedAccessException"/>, simulando
/// una sottodirectory illeggibile (permessi negati) incontrata durante la somma ricorsiva delle
/// dimensioni. A differenza di <see cref="VanishingChildFileSystem"/> (che scompare una tantum),
/// qui <c>Directory.Exists</c> continua a restituire true per il percorso: la directory esiste
/// ed è visibile, semplicemente non è elencabile.
/// </summary>
internal sealed class UnreadableDirectoryFileSystem(IFileSystem inner, string unreadablePath) : IFileSystem
{
    public IDirectory Directory { get; } = UnreadableDirectoryProxy.Wrap(inner.Directory, unreadablePath);

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
/// Proxy dinamico su <see cref="IDirectory"/>: inoltra ogni membro all'istanza reale, tranne
/// <c>EnumerateFileSystemEntries</c> sul percorso bersaglio, che lancia
/// <see cref="UnauthorizedAccessException"/> ogni volta. Usa <see cref="DispatchProxy"/> come i
/// doppi analoghi in questo progetto, per non dover implementare a mano tutti i membri di
/// <c>IDirectory</c> che il codice sotto test non chiama comunque per questo scenario.
/// </summary>
internal class UnreadableDirectoryProxy : DispatchProxy
{
    private IDirectory _inner = null!;
    private string _target = null!;

    protected override object? Invoke(MethodInfo? targetMethod, object?[]? args)
    {
        if (targetMethod!.Name == nameof(IDirectory.EnumerateFileSystemEntries)
            && args is { Length: > 0 } && args[0] is string path
            && path == _target)
        {
            throw new UnauthorizedAccessException($"Accesso negato: {path}");
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

    public static IDirectory Wrap(IDirectory inner, string target)
    {
        object proxy = Create<IDirectory, UnreadableDirectoryProxy>()!;
        UnreadableDirectoryProxy typed = (UnreadableDirectoryProxy)proxy;
        typed._inner = inner;
        typed._target = target;
        return (IDirectory)proxy;
    }
}
