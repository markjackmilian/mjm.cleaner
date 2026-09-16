using System.IO.Abstractions;
using System.Reflection;

namespace MjmCleaner.Core.Tests.Scanning;

/// <summary>
/// Decora un <see cref="IFileSystem"/> in modo che la lettura di <c>FileInfo.Length</c> su un
/// percorso specifico fallisca con <see cref="FileNotFoundException"/>, simulando un elemento
/// che scompare fra l'enumerazione di una directory e la lettura della sua dimensione — una
/// vera corsa critica, non solo un percorso mai aggiunto al filesystem simulato: quest'ultimo
/// non eserciterebbe affatto il ramo "elencato ma poi introvabile" che il test deve coprire.
/// </summary>
internal sealed class VanishingFileSystem(IFileSystem inner, string vanishedPath) : IFileSystem
{
    public IDirectory Directory => inner.Directory;

    public IDirectoryInfoFactory DirectoryInfo => inner.DirectoryInfo;

    public IDriveInfoFactory DriveInfo => inner.DriveInfo;

    public IFile File => inner.File;

    public IFileInfoFactory FileInfo { get; } = new VanishingFileInfoFactory(inner.FileInfo, vanishedPath);

    public IFileStreamFactory FileStream => inner.FileStream;

    public IFileSystemWatcherFactory FileSystemWatcher => inner.FileSystemWatcher;

    public IFileVersionInfoFactory FileVersionInfo => inner.FileVersionInfo;

    public IPath Path => inner.Path;
}

internal sealed class VanishingFileInfoFactory(IFileInfoFactory inner, string vanishedPath) : IFileInfoFactory
{
    public IFileSystem FileSystem => inner.FileSystem;

    public IFileInfo New(string fileName)
    {
        IFileInfo real = inner.New(fileName);
        return fileName == vanishedPath ? ThrowingFileInfoProxy.Wrap(real, vanishedPath) : real;
    }

    public IFileInfo? Wrap(FileInfo? fileInfo) => inner.Wrap(fileInfo);
}

/// <summary>
/// Proxy dinamico su <see cref="IFileInfo"/>: inoltra ogni membro all'istanza reale, tranne
/// <c>Length</c>, che lancia <see cref="FileNotFoundException"/>. Usa <see cref="DispatchProxy"/>
/// invece di implementare a mano tutti i membri (ereditati da <c>IFileSystemInfo</c>) che il
/// codice sotto test non chiama comunque per questo percorso.
/// </summary>
internal class ThrowingFileInfoProxy : DispatchProxy
{
    private IFileInfo _inner = null!;
    private string _path = null!;

    protected override object? Invoke(MethodInfo? targetMethod, object?[]? args)
    {
        if (targetMethod!.Name == "get_Length")
        {
            throw new FileNotFoundException("Il file è scomparso durante la scansione.", _path);
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

    public static IFileInfo Wrap(IFileInfo inner, string path)
    {
        object proxy = Create<IFileInfo, ThrowingFileInfoProxy>()!;
        ThrowingFileInfoProxy target = (ThrowingFileInfoProxy)proxy;
        target._inner = inner;
        target._path = path;
        return (IFileInfo)proxy;
    }
}
