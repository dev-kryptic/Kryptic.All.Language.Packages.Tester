"""Kryptic Python package verification.

Injects secrets from the local daemon and reports what landed in os.environ.
"""
import os
import sys

import kryptic


def main() -> int:
    before = set(os.environ)

    result = kryptic.inject()

    if result.skipped:
        print(f"SKIPPED ({result.reason}) - nothing injected.")
        print("If you expected secrets: is the daemon running (`kryptic status`) and are you signed in?")
        return 1

    injected = sorted(set(os.environ) - before)

    print(f"injected {result.injected} secret(s):")
    for key in injected:
        print(f"  env     {key} = {os.environ[key]}")

    if not injected:
        print("  (the project has no secrets in this environment)")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:  # noqa: BLE001 - the package must never raise
        print(f"UNEXPECTED ERROR - the package should never raise: {error}", file=sys.stderr)
        sys.exit(1)
