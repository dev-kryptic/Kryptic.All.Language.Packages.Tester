using Microsoft.Extensions.Configuration;
using StackExchange.Redis;

sealed class RedisTemplate : ITemplate
{
    public string Id => "redis";
    public string DefaultKey => "Dynamic_Redis";

    public async Task<int> Execute(IConfiguration configuration, string key)
    {
        if (!LeaseAccess.TryUserPassword(configuration, key, out var username, out var password))
            return 1;

        var host = Environment.GetEnvironmentVariable("REDIS_HOST") ?? "localhost";
        var port = int.Parse(Environment.GetEnvironmentVariable("REDIS_PORT") ?? "6379");

        var options = new ConfigurationOptions
        {
            EndPoints = { { host, port } },
            User = username,
            Password = password,
            Ssl = !LeaseAccess.IsLocal(host),
            AbortOnConnectFail = true,
            ConnectTimeout = 10_000,
        };

        await using var mux = await ConnectionMultiplexer.ConnectAsync(options);
        var pong = await mux.GetDatabase().PingAsync();

        Console.WriteLine("redis lease works");
        Console.WriteLine($"  key        {key}");
        Console.WriteLine($"  username   {username}");
        Console.WriteLine($"  ping       {pong.TotalMilliseconds:0} ms");
        return 0;
    }
}
