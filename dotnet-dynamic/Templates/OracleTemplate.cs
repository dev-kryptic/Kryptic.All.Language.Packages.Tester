using Microsoft.Extensions.Configuration;
using Oracle.ManagedDataAccess.Client;

sealed class OracleTemplate : ITemplate
{
    public string Id => "oracle";
    public string DefaultKey => "Dynamic_Oracle";

    public async Task<int> Execute(IConfiguration configuration, string key)
    {
        if (!LeaseAccess.TryUserPassword(configuration, key, out var username, out var password))
            return 1;

        var host = Environment.GetEnvironmentVariable("ORACLE_HOST") ?? "localhost";
        var port = Environment.GetEnvironmentVariable("ORACLE_PORT") ?? "1521";
        var service = Environment.GetEnvironmentVariable("ORACLE_SERVICE") ?? "FREEPDB1";

        var builder = new OracleConnectionStringBuilder
        {
            UserID = username,
            Password = password,
            DataSource = $"{host}:{port}/{service}",
        };

        await using var connection = new OracleConnection(builder.ConnectionString);
        await connection.OpenAsync();
        await using var command = new OracleCommand("select user, sys_context('USERENV', 'SERVICE_NAME') from dual", connection);
        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
        {
            Console.Error.WriteLine("oracle: connected, but dual returned no row.");
            return 1;
        }

        Console.WriteLine("oracle lease works");
        Console.WriteLine($"  key        {key}");
        Console.WriteLine($"  username   {reader.GetString(0)}");
        Console.WriteLine($"  service    {reader.GetString(1)}");
        return 0;
    }
}
