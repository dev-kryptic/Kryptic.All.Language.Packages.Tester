using Microsoft.Extensions.Configuration;

static class LeaseAccess
{
    public static string? Get(IConfiguration configuration, string key, string suffix) =>
        configuration[$"{key}_{suffix}"];

    public static bool TryUserPassword(
        IConfiguration configuration,
        string key,
        out string username,
        out string password)
    {
        username = Get(configuration, key, "USERNAME") ?? "";
        password = Get(configuration, key, "PASSWORD") ?? "";
        if (username.Length > 0 && password.Length > 0) return true;
        Console.Error.WriteLine($"No {key}_USERNAME / {key}_PASSWORD from the daemon.");
        Console.Error.WriteLine("Is the daemon signed in, the connector running, and kryptic.json the right project?");
        return false;
    }

    public static bool IsLocal(string host) =>
        host is "localhost" or "127.0.0.1" or "::1";
}
