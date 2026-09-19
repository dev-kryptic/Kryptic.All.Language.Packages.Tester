using Microsoft.Extensions.Configuration;
using MySqlConnector;

sealed class MySqlTemplate : ITemplate
{
    public string Id => "mysql";
    public string DefaultKey => "Dynamic_MySQL";

    public async Task<int> Execute(IConfiguration configuration, string key)
    {
        if (!LeaseAccess.TryUserPassword(configuration, key, out var username, out var password))
            return 1;

        var host = Environment.GetEnvironmentVariable("MYSQL_HOST") ?? "localhost";
        var port = int.Parse(Environment.GetEnvironmentVariable("MYSQL_PORT") ?? "3306");
        var database = Environment.GetEnvironmentVariable("MYSQL_DATABASE") ?? "kryptic_dynamic_secrets_test";

        var builder = new MySqlConnectionStringBuilder
        {
            Server = host,
            Port = (uint)port,
            Database = database,
            UserID = username,
            Password = password,
            SslMode = LeaseAccess.IsLocal(host) ? MySqlSslMode.Disabled : MySqlSslMode.Preferred,
        };

        await using var connection = new MySqlConnection(builder.ConnectionString);
        await connection.OpenAsync();
        await using var command = new MySqlCommand("select current_user(), database()", connection);
        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
        {
            Console.Error.WriteLine("mysql: connected, but the probe query returned no row.");
            return 1;
        }

        Console.WriteLine("mysql lease works");
        Console.WriteLine($"  key        {key}");
        Console.WriteLine($"  username   {reader.GetString(0)}");
        Console.WriteLine($"  database   {reader.GetString(1)}");
        return 0;
    }
}
