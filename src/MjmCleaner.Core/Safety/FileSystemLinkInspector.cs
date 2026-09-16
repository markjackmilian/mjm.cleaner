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
}
