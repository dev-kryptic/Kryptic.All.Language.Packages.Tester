// Kryptic Node.js package verification.
// Injects secrets from the local daemon and reports exactly what landed in
// process.env - the same check the .NET runner does for IConfiguration.
const kryptic = require('kryptic-daemon-client');

async function main() {
  const before = new Set(Object.keys(process.env));

  const result = await kryptic.inject();

  if (result.skipped) {
    console.log(`SKIPPED (${result.reason}) - nothing injected.`);
    console.log('If you expected secrets: is the daemon running (`kryptic status`) and are you signed in?');
    process.exit(1);
  }

  const injected = Object.keys(process.env)
    .filter((key) => !before.has(key))
    .sort();

  console.log(`injected ${result.injected} secret(s):`);
  for (const key of injected) {
    console.log(`  env     ${key} = ${process.env[key]}`);
  }

  if (injected.length === 0) {
    console.log('  (the project has no secrets in this environment)');
  }
}

main().catch((error) => {
  // The package must never throw; reaching here is itself a failure.
  console.error('UNEXPECTED ERROR - the package should never throw:', error);
  process.exit(1);
});
