package dev.kryptic.testrunner;

import dev.kryptic.Kryptic;

import java.util.Map;
import java.util.TreeMap;

/**
 * Kryptic Java package verification: injects secrets from the local daemon and
 * reports what landed in the system properties (the JVM cannot modify its own
 * process environment, so the Java package uses properties instead).
 */
public final class Main {

    public static void main(String[] args) {
        try {
            Kryptic.Result result = Kryptic.inject();

            if (result.skipped()) {
                System.out.printf("SKIPPED (%s) - nothing injected.%n", result.reason());
                System.out.println("If you expected secrets: is the daemon running (`kryptic status`) and are you signed in?");
                System.exit(1);
            }

            // fetch() returns the same bundle without touching properties, so
            // the report can name exactly the injected keys.
            Map<String, String> secrets = new TreeMap<>(Kryptic.fetch());

            System.out.printf("injected %d secret(s):%n", result.injected());
            for (Map.Entry<String, String> entry : secrets.entrySet()) {
                System.out.printf("  property %s = %s%n", entry.getKey(), System.getProperty(entry.getKey()));
            }

            if (secrets.isEmpty()) {
                System.out.println("  (the project has no secrets in this environment)");
            }
        } catch (RuntimeException e) {
            System.err.println("UNEXPECTED ERROR - the package should never throw: " + e);
            System.exit(1);
        }
    }

    private Main() {
    }
}
