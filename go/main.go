// Kryptic Go package verification: injects secrets from the local daemon and
// reports what landed in the process environment.
package main

import (
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/dev-kryptic/Kryptic.Go"
)

func main() {
	before := map[string]bool{}
	for _, entry := range os.Environ() {
		before[strings.SplitN(entry, "=", 2)[0]] = true
	}

	result := kryptic.Inject()

	if result.Skipped {
		fmt.Printf("SKIPPED (%s) - nothing injected.\n", result.Reason)
		fmt.Println("If you expected secrets: is the daemon running (`kryptic status`) and are you signed in?")
		os.Exit(1)
	}

	var injected []string
	for _, entry := range os.Environ() {
		key := strings.SplitN(entry, "=", 2)[0]
		if !before[key] {
			injected = append(injected, key)
		}
	}
	sort.Strings(injected)

	fmt.Printf("injected %d secret(s):\n", result.Injected)
	for _, key := range injected {
		fmt.Printf("  env     %s = %s\n", key, os.Getenv(key))
	}

	if len(injected) == 0 {
		fmt.Println("  (the project has no secrets in this environment)")
	}
}
