using Microsoft.Extensions.Configuration;

interface ITemplate
{
    string Id { get; }
    string DefaultKey { get; }
    Task<int> Execute(IConfiguration configuration, string key);
}
