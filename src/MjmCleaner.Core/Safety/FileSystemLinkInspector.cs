using System.IO.Abstractions;

namespace MjmCleaner.Core.Safety;

public sealed class FileSystemLinkInspector(IFileSystem fileSystem) : ILinkInspector
{
    public bool IsSymbolicLink(string path)
    {
        try
        {
            if (fileSystem.Directory.Exists(path))
            {
                return fileSystem.DirectoryInfo.New(path).LinkTarget is not null;
            }

            return fileSystem.File.Exists(path)
                && fileSystem.FileInfo.New(path).LinkTarget is not null;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    public string? ResolveLinkTarget(string path)
    {
        try
        {
            if (fileSystem.Directory.Exists(path))
            {
                return fileSystem.DirectoryInfo.New(path).ResolveLinkTarget(returnFinalTarget: true)?.FullName;
            }

            if (fileSystem.File.Exists(path))
            {
                return fileSystem.FileInfo.New(path).ResolveLinkTarget(returnFinalTarget: true)?.FullName;
            }

            return null;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }
}
