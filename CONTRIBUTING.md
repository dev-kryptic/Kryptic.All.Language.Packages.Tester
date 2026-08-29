# Contributing

This repository is the hands-on check that daemon, local socket, language
package, and process environment work together on the machine you are testing.

## What we accept

- Fixes when a runner fails to report injected secrets
- A new runner only when a new language package exists
- Documentation corrections

## What we do not accept

- Public GitHub issues for vulnerabilities (email security@kryptic.dev)

## Development

```bash
./install-deps.sh   # once, if language toolchains are missing
./run-all.sh
```

The daemon must be running and signed in (`kryptic status`). Each directory
uses the same `kryptic.json`.

## Licensing of contributions

This repository is Apache-2.0. By opening a pull request you confirm the
contribution is your own work (or you have the right to submit it) and you
license it under Apache-2.0. There is no CLA.

## Code of conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
