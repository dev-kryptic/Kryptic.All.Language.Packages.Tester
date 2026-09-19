using Cassandra;
using Microsoft.Extensions.Configuration;

sealed class CassandraTemplate : ITemplate
{
    public string Id => "cassandra";
    public string DefaultKey => "Dynamic_Cassandra";

    public Task<int> Execute(IConfiguration configuration, string key)
    {
        if (!LeaseAccess.TryUserPassword(configuration, key, out var username, out var password))
            return Task.FromResult(1);

        var hosts = (Environment.GetEnvironmentVariable("CASSANDRA_HOSTS") ?? "localhost")
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var port = int.Parse(Environment.GetEnvironmentVariable("CASSANDRA_PORT") ?? "9042");
        var keyspace = Environment.GetEnvironmentVariable("CASSANDRA_KEYSPACE");

        var builder = Cluster.Builder()
            .AddContactPoints(hosts)
            .WithPort(port)
            .WithCredentials(username, password);
        var dc = Environment.GetEnvironmentVariable("CASSANDRA_DC");
        if (!string.IsNullOrWhiteSpace(dc))
            builder = builder.WithLoadBalancingPolicy(new DCAwareRoundRobinPolicy(dc));

        using var cluster = builder.Build();
        using var session = string.IsNullOrWhiteSpace(keyspace)
            ? cluster.Connect()
            : cluster.Connect(keyspace);

        var row = session.Execute("select release_version, cluster_name from system.local").FirstOrDefault();
        if (row is null)
        {
            Console.Error.WriteLine("cassandra: connected, but system.local returned no row.");
            return Task.FromResult(1);
        }

        Console.WriteLine("cassandra lease works");
        Console.WriteLine($"  key        {key}");
        Console.WriteLine($"  username   {username}");
        Console.WriteLine($"  cluster    {row.GetValue<string>("cluster_name")}");
        Console.WriteLine($"  version    {row.GetValue<string>("release_version")}");
        if (!string.IsNullOrWhiteSpace(keyspace))
            Console.WriteLine($"  keyspace   {keyspace}");
        return Task.FromResult(0);
    }
}
