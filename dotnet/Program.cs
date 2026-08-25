using Kryptic;
using Microsoft.Extensions.Configuration;

var configuration = new ConfigurationBuilder()
    .AddKryptic()
    .Build();

// The only configuration source is Kryptic, so every entry here is an injected secret.
var secrets = configuration.AsEnumerable()
     .Where(pair => pair.Value is not null)
     .OrderBy(pair => pair.Key)
     .ToList();

Console.WriteLine($"injected {secrets.Count} secret(s):");
foreach (var (key, value) in secrets)
{
     Console.WriteLine($"  config  {key} = {value}");
     // Console.WriteLine($"  env     {key} = {Environment.GetEnvironmentVariable(key) ?? "(null)"}");
}
