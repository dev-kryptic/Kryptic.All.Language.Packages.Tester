# Kryptic Test Runner

One tiny application per supported language that integrates the Kryptic package,
pulls secrets from the local daemon, and prints exactly what was injected. This
is the hands-on check that the whole chain works:
**daemon -> local socket -> package -> your process environment** on the machine
and OS you are testing.

Every runner uses the same `kryptic.json`, so all seven should print the same
secrets.

## Before you start

```bash
kryptic status      # daemon: online - signed in as you@company.com
```

If it says *not running* or *not signed in*, run `kryptic start` and
`kryptic login` first. Then point `kryptic.json` in each directory at a project
you can read (copy it from the project page in the dashboard).

## Run everything

```bash
./run-all.sh
```

Or one language at a time:

```bash
./run-all.sh node python
```

The script prints a pass/fail line per language and exits non-zero if any
failed.

## Run them individually

| Language | Command | Package |
| --- | --- | --- |
| .NET | `cd dotnet && dotnet run` | `Kryptic.Daemon.Client` on NuGet |
| Node.js | `cd node && npm install && node index.js` | `kryptic-daemon-client` on npm |
| Python | `cd python && pip install -r requirements.txt && python main.py` | `kryptic-daemon-client` on PyPI |
| Go | `cd go && go run .` | `github.com/dev-kryptic/Kryptic.Go@v0.1.0` |
| Ruby | `cd ruby && bundle install && bundle exec ruby main.rb` | `kryptic-daemon-client` on RubyGems |
| Java | `cd java && mvn compile exec:java` | `dev.kryptic:daemon-client` on Maven Central |
| C++ | `cd cpp && cmake -S . -B build && cmake --build build && ./build/kryptic-test-runner` | `dev-kryptic/Kryptic.Cpp` `v0.1.0` via FetchContent |

The .NET runner uses `AddKryptic()` and reports `IConfiguration`. The Java runner
reports system properties, because the JVM cannot set its own process environment.

## What a pass looks like

```
injected 3 secret(s):
  env     DATABASE_URL = postgres://…
  env     REDIS_URL = redis://…
  env     STRIPE_API_KEY = sk_test_…
```

## What the failures mean

| Output | Cause |
| --- | --- |
| `SKIPPED (daemon_unreachable)` | The daemon is not running, or `KRYPTIC_SOCKET_PATH` points somewhere wrong |
| `SKIPPED (not_authenticated)` | Daemon is up but has no session. Run `kryptic login`. |
| `SKIPPED (no_project)` | No `kryptic.json` found walking up from the working directory |
| `SKIPPED (access_denied)` | Your account has no access to that project/environment |
| `SKIPPED (node_env_production)` etc. | The runtime says this is production, so the package correctly no-ops |
| `injected 0 secret(s)` | Everything worked. The project simply has no secrets in this environment. |
| `UNEXPECTED ERROR` | A real bug: the packages must never throw into the host application |

## Testing other environments and platforms

```bash
KRYPTIC_ENV=staging ./run-all.sh          # a different environment
KRYPTIC_DISABLED=true ./run-all.sh        # every runner should report SKIPPED (disabled)
NODE_ENV=production node index.js          # the Node runner should no-op
```

On Windows the same runners exercise the named-pipe transport instead of unix
sockets. Run them from PowerShell with the daemon (or tray app) running.
