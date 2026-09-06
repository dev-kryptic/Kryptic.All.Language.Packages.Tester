package dev.kryptic.testrunner;

import dev.kryptic.Kryptic;
import dev.kryptic.spring.EnableKryptic;
import java.util.Arrays;
import org.springframework.boot.Banner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.EnumerablePropertySource;
import org.springframework.core.env.Environment;
import org.springframework.core.env.PropertySource;

/**
 * Kryptic Spring Boot package verification: {@code @EnableKryptic} feeds
 * {@code Kryptic.fetch()} into the Spring Environment, and this runner reports
 * what landed in the {@code kryptic} property source.
 */
@SpringBootApplication
@EnableKryptic
public class Application {

    public static void main(String[] args) {
        try {
            SpringApplication app = new SpringApplication(Application.class);
            app.setWebApplicationType(WebApplicationType.NONE);
            app.setBannerMode(Banner.Mode.OFF);
            app.setLogStartupInfo(false);
            System.exit(report(app.run(args).getEnvironment()));
        } catch (RuntimeException e) {
            System.err.println("UNEXPECTED ERROR - the package should never throw: " + e);
            System.exit(1);
        }
    }

    private static int report(Environment environment) {
        if (!(environment instanceof ConfigurableEnvironment configurable)) {
            System.out.println("SKIPPED (no_environment) - nothing injected.");
            return 1;
        }

        PropertySource<?> source = configurable.getPropertySources().get("kryptic");
        if (source == null) {
            Kryptic.Result result = Kryptic.inject();
            if (result.skipped()) {
                System.out.printf("SKIPPED (%s) - nothing injected.%n", result.reason());
                System.out.println("If you expected secrets: is the daemon running (`kryptic status`) and are you signed in?");
                return 1;
            }
            System.out.println("injected 0 secret(s):");
            System.out.println("  (the project has no secrets in this environment)");
            return 0;
        }

        String[] names = source instanceof EnumerablePropertySource<?> enumerable
            ? enumerable.getPropertyNames()
            : new String[0];
        Arrays.sort(names);

        System.out.printf("injected %d secret(s):%n", names.length);
        for (String name : names) {
            System.out.printf("  config  %s = %s%n", name, environment.getProperty(name));
        }
        return 0;
    }
}
