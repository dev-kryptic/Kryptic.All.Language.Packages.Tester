using Kryptic;
using Microsoft.Extensions.Configuration;

// Proves a dynamic lease for each provider template.
// Daemon injects KEY_USERNAME / KEY_PASSWORD (AWS also ACCESS_KEY_ID / SESSION_TOKEN).
//
// 1. docker compose up -d   from Kryptic.Test.Runner (Postgres, MySQL, Redis, Cassandra, Oracle)
// 2. kryptic start && kryptic login
// 3. Start "Dynamic-Secrets" Connector (or kryptic connector run --name local)
// 4. Paste this project's id into kryptic.json
// 5. Save each provider envelope against localhost (see docker-compose.yml)
// 6. DOTNET_ENVIRONMENT=Development (launchSettings does this)
//
//   dotnet run -- postgres
//   dotnet run -- mysql Dynamic_MySQL
//   dotnet run -- all
//
// Default with no args is postgres (the key already in this project).
// AWS is not in compose. Skip it, or point a key at a real account.

ITemplate[] templates =
[
    new PostgresTemplate(),
    new MySqlTemplate(),
    new CassandraTemplate(),
    new OracleTemplate(),
    new RedisTemplate(),
    new AwsIamTemplate(),
];

var selected = args.ElementAtOrDefault(0) ?? "postgres";
var keyOverride = args.ElementAtOrDefault(1)
    ?? Environment.GetEnvironmentVariable("DYNAMIC_SECRET_KEY");

var run = selected.Equals("all", StringComparison.OrdinalIgnoreCase)
    ? templates
    : templates.Where(t => t.Id.Equals(selected, StringComparison.OrdinalIgnoreCase)).ToArray();

if (run.Length == 0)
{
    Console.Error.WriteLine($"Unknown template '{selected}'.");
    Console.Error.WriteLine("Use: postgres | mysql | cassandra | oracle | redis | aws | all");
    return 1;
}

Console.WriteLine("Asking the daemon for a lease (this can take up to 90s)...");
var configuration = new ConfigurationBuilder()
    .AddKryptic(options => options.SocketTimeoutMs = 120_000)
    .Build();

var failed = 0;
foreach (var template in run)
{
    var key = keyOverride ?? template.DefaultKey;
    Console.WriteLine();
    Console.WriteLine($"== {template.Id} ({key}) ==");
    try
    {
        if (await template.Execute(configuration, key) != 0)
            failed++;
    }
    catch (Exception ex)
    {
        failed++;
        Console.Error.WriteLine($"{template.Id}: {ex.Message}");
    }
}

return failed == 0 ? 0 : 1;
