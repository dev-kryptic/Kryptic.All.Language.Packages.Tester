using Microsoft.Extensions.Configuration;
using Npgsql;

sealed class PostgresTemplate : ITemplate
{
    public string Id => "postgres";
    public string DefaultKey => "Dynamic_Secrets_Test";

    public async Task<int> Execute(IConfiguration configuration, string key)
    {
        if (!LeaseAccess.TryUserPassword(configuration, key, out var username, out var password))
            return 1;

        var host = Environment.GetEnvironmentVariable("PGHOST") ?? "localhost";
        var port = int.Parse(Environment.GetEnvironmentVariable("PGPORT") ?? "5432");
        var database = Environment.GetEnvironmentVariable("PGDATABASE") ?? "kryptic_dynamic_secrets_test";

        var builder = new NpgsqlConnectionStringBuilder
        {
            Host = host,
            Port = port,
            Database = database,
            Username = username,
            Password = password,
            SslMode = LeaseAccess.IsLocal(host) ? SslMode.Disable : SslMode.Prefer,
        };

        await using var connection = new NpgsqlConnection(builder.ConnectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "select current_user, session_user, current_database()",
            connection);
        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
        {
            Console.Error.WriteLine("postgres: connected, but the probe query returned no row.");
            return 1;
        }

        Console.WriteLine("postgres lease works");
        Console.WriteLine($"  key        {key}");
        Console.WriteLine($"  username   {reader.GetString(0)}");
        Console.WriteLine($"  session    {reader.GetString(1)}");
        Console.WriteLine($"  database   {reader.GetString(2)}");
        return 0;
    }
}
