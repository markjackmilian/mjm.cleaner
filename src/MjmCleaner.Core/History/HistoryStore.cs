using Microsoft.Data.Sqlite;
using MjmCleaner.Core.Cleaning;

namespace MjmCleaner.Core.History;

public sealed record CleanSessionSummary(
    long Id,
    DateTimeOffset StartedAtUtc,
    TimeSpan Duration,
    long BytesFreed,
    int ItemsDeleted,
    int ItemsFailed,
    IReadOnlyList<CategoryCleanResult> Categories);

public interface IHistoryStore
{
    Task InitializeAsync(CancellationToken ct);
    Task<long> SaveAsync(CleanReport report, CancellationToken ct);
    Task<IReadOnlyList<CleanSessionSummary>> GetSessionsAsync(int limit, CancellationToken ct);
    Task<long> GetTotalBytesFreedAsync(CancellationToken ct);
}

public sealed class HistoryStore(string databaseFile) : IHistoryStore
{
    private const int SchemaVersion = 1;

    private string ConnectionString => new SqliteConnectionStringBuilder
    {
        DataSource = databaseFile,
        Mode = SqliteOpenMode.ReadWriteCreate,
    }.ToString();

    public async Task InitializeAsync(CancellationToken ct)
    {
        string? directory = Path.GetDirectoryName(databaseFile);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        await using SqliteConnection connection = new(ConnectionString);
        await connection.OpenAsync(ct);

        await using SqliteCommand command = connection.CreateCommand();
        command.CommandText = $"""
            CREATE TABLE IF NOT EXISTS CleanSession (
              Id           INTEGER PRIMARY KEY AUTOINCREMENT,
              StartedAtUtc TEXT    NOT NULL,
              DurationMs   INTEGER NOT NULL,
              BytesFreed   INTEGER NOT NULL,
              ItemsDeleted INTEGER NOT NULL,
              ItemsFailed  INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS SessionCategory (
              SessionId    INTEGER NOT NULL REFERENCES CleanSession(Id) ON DELETE CASCADE,
              CategoryId   TEXT    NOT NULL,
              BytesFreed   INTEGER NOT NULL,
              ItemsDeleted INTEGER NOT NULL,
              PRIMARY KEY (SessionId, CategoryId)
            );

            PRAGMA user_version = {SchemaVersion};
            """;

        await command.ExecuteNonQueryAsync(ct);
    }

    public async Task<long> SaveAsync(CleanReport report, CancellationToken ct)
    {
        await using SqliteConnection connection = new(ConnectionString);
        await connection.OpenAsync(ct);
        await using SqliteTransaction transaction = (SqliteTransaction)await connection.BeginTransactionAsync(ct);

        await using SqliteCommand insertSession = connection.CreateCommand();
        insertSession.Transaction = transaction;
        insertSession.CommandText = """
            INSERT INTO CleanSession (StartedAtUtc, DurationMs, BytesFreed, ItemsDeleted, ItemsFailed)
            VALUES ($startedAt, $duration, $bytes, $deleted, $failed);
            SELECT last_insert_rowid();
            """;
        insertSession.Parameters.AddWithValue("$startedAt", report.StartedAtUtc.UtcDateTime.ToString("O"));
        insertSession.Parameters.AddWithValue("$duration", (long)report.Duration.TotalMilliseconds);
        insertSession.Parameters.AddWithValue("$bytes", report.BytesFreed);
        insertSession.Parameters.AddWithValue("$deleted", report.ItemsDeleted);
        insertSession.Parameters.AddWithValue("$failed", report.ItemsFailed);

        long sessionId = (long)(await insertSession.ExecuteScalarAsync(ct))!;

        foreach (CategoryCleanResult category in report.Categories)
        {
            await using SqliteCommand insertCategory = connection.CreateCommand();
            insertCategory.Transaction = transaction;
            insertCategory.CommandText = """
                INSERT INTO SessionCategory (SessionId, CategoryId, BytesFreed, ItemsDeleted)
                VALUES ($session, $category, $bytes, $deleted);
                """;
            insertCategory.Parameters.AddWithValue("$session", sessionId);
            insertCategory.Parameters.AddWithValue("$category", category.CategoryId);
            insertCategory.Parameters.AddWithValue("$bytes", category.BytesFreed);
            insertCategory.Parameters.AddWithValue("$deleted", category.ItemsDeleted);
            await insertCategory.ExecuteNonQueryAsync(ct);
        }

        await transaction.CommitAsync(ct);
        return sessionId;
    }

    public async Task<IReadOnlyList<CleanSessionSummary>> GetSessionsAsync(int limit, CancellationToken ct)
    {
        await using SqliteConnection connection = new(ConnectionString);
        await connection.OpenAsync(ct);

        Dictionary<long, List<CategoryCleanResult>> categories = [];

        await using (SqliteCommand categoryCommand = connection.CreateCommand())
        {
            categoryCommand.CommandText = """
                SELECT SessionId, CategoryId, BytesFreed, ItemsDeleted
                FROM SessionCategory
                WHERE SessionId IN (SELECT Id FROM CleanSession ORDER BY Id DESC LIMIT $limit);
                """;
            categoryCommand.Parameters.AddWithValue("$limit", limit);

            await using SqliteDataReader reader = await categoryCommand.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                long sessionId = reader.GetInt64(0);
                if (!categories.TryGetValue(sessionId, out List<CategoryCleanResult>? list))
                {
                    list = [];
                    categories[sessionId] = list;
                }

                list.Add(new CategoryCleanResult(reader.GetString(1), reader.GetInt64(2), reader.GetInt32(3)));
            }
        }

        List<CleanSessionSummary> sessions = [];

        await using SqliteCommand command = connection.CreateCommand();
        command.CommandText = """
            SELECT Id, StartedAtUtc, DurationMs, BytesFreed, ItemsDeleted, ItemsFailed
            FROM CleanSession
            ORDER BY Id DESC
            LIMIT $limit;
            """;
        command.Parameters.AddWithValue("$limit", limit);

        await using SqliteDataReader sessionReader = await command.ExecuteReaderAsync(ct);
        while (await sessionReader.ReadAsync(ct))
        {
            long id = sessionReader.GetInt64(0);
            sessions.Add(new CleanSessionSummary(
                id,
                DateTimeOffset.Parse(sessionReader.GetString(1), null, System.Globalization.DateTimeStyles.AssumeUniversal | System.Globalization.DateTimeStyles.AdjustToUniversal),
                TimeSpan.FromMilliseconds(sessionReader.GetInt64(2)),
                sessionReader.GetInt64(3),
                sessionReader.GetInt32(4),
                sessionReader.GetInt32(5),
                categories.TryGetValue(id, out List<CategoryCleanResult>? list) ? list : []));
        }

        return sessions;
    }

    /// <summary>Somma calcolata, non un contatore memorizzato: un contatore prima o poi diverge dalle righe.</summary>
    public async Task<long> GetTotalBytesFreedAsync(CancellationToken ct)
    {
        await using SqliteConnection connection = new(ConnectionString);
        await connection.OpenAsync(ct);

        await using SqliteCommand command = connection.CreateCommand();
        command.CommandText = "SELECT COALESCE(SUM(BytesFreed), 0) FROM CleanSession;";

        return (long)(await command.ExecuteScalarAsync(ct))!;
    }
}
