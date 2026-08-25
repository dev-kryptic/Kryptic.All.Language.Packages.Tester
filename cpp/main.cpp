// Kryptic C++ package verification: injects secrets from the local daemon and
// reports what landed in the process environment.
#include <kryptic/kryptic.hpp>

#include <cstdlib>
#include <iostream>
#include <set>
#include <string>
#include <vector>

#ifdef _WIN32
#include <stdlib.h>
#else
extern char** environ;
#endif

static std::set<std::string> snapshot_keys() {
    std::set<std::string> keys;
#ifdef _WIN32
    for (char** entry = _environ; entry && *entry; ++entry) {
#else
    for (char** entry = environ; entry && *entry; ++entry) {
#endif
        const std::string line(*entry);
        const auto eq = line.find('=');
        keys.insert(eq == std::string::npos ? line : line.substr(0, eq));
    }
    return keys;
}

int main() {
    const auto before = snapshot_keys();
    const auto result = kryptic::inject();

    if (result.skipped) {
        std::cout << "SKIPPED (" << result.reason << ") - nothing injected.\n";
        std::cout << "If you expected secrets: is the daemon running (`kryptic status`) and are you signed in?\n";
        return 1;
    }

    std::vector<std::string> injected;
    const auto after = snapshot_keys();
    for (const auto& key : after) {
        if (!before.count(key)) injected.push_back(key);
    }

    std::cout << "injected " << result.injected << " secret(s):\n";
    for (const auto& key : injected) {
        const char* value = std::getenv(key.c_str());
        std::cout << "  env     " << key << " = " << (value ? value : "") << '\n';
    }
    if (injected.empty()) {
        std::cout << "  (the project has no secrets in this environment)\n";
    }
    return 0;
}
