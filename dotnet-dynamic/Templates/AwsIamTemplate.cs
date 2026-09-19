using Amazon;
using Amazon.Runtime;
using Amazon.SecurityToken;
using Amazon.SecurityToken.Model;
using Microsoft.Extensions.Configuration;

sealed class AwsIamTemplate : ITemplate
{
    public string Id => "aws";
    public string DefaultKey => "Dynamic_AwsIam";

    public async Task<int> Execute(IConfiguration configuration, string key)
    {
        var accessKey = LeaseAccess.Get(configuration, key, "ACCESS_KEY_ID");
        var secret = LeaseAccess.Get(configuration, key, "PASSWORD");
        var session = LeaseAccess.Get(configuration, key, "SESSION_TOKEN");
        var username = LeaseAccess.Get(configuration, key, "USERNAME");
        if (string.IsNullOrEmpty(accessKey) || string.IsNullOrEmpty(secret))
        {
            Console.Error.WriteLine($"No {key}_ACCESS_KEY_ID / {key}_PASSWORD from the daemon.");
            return 1;
        }

        AWSCredentials credentials = string.IsNullOrEmpty(session)
            ? new BasicAWSCredentials(accessKey, secret)
            : new SessionAWSCredentials(accessKey, secret, session);

        var regionName = Environment.GetEnvironmentVariable("AWS_REGION") ?? "eu-central-1";
        using var sts = new AmazonSecurityTokenServiceClient(credentials, RegionEndpoint.GetBySystemName(regionName));
        var identity = await sts.GetCallerIdentityAsync(new GetCallerIdentityRequest());

        Console.WriteLine("aws iam lease works");
        Console.WriteLine($"  key        {key}");
        if (!string.IsNullOrEmpty(username))
            Console.WriteLine($"  username   {username}");
        Console.WriteLine($"  account    {identity.Account}");
        Console.WriteLine($"  arn        {identity.Arn}");
        Console.WriteLine($"  user id    {identity.UserId}");
        return 0;
    }
}
