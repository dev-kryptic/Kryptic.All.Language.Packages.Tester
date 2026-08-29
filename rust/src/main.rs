// Kryptic Rust package verification: injects secrets from the local daemon and
// reports what landed in the process environment.
use std::collections::HashSet;
use std::env;
use std::process;

fn main() {
    let before: HashSet<String> = env::vars().map(|(key, _)| key).collect();

    let result = kryptic::inject();

    if result.skipped {
        let reason = result.reason.as_deref().unwrap_or("unknown");
        println!("SKIPPED ({reason}) - nothing injected.");
        println!(
            "If you expected secrets: is the daemon running (`kryptic status`) and are you signed in?"
        );
        process::exit(1);
    }

    let mut injected: Vec<String> = env::vars()
        .map(|(key, _)| key)
        .filter(|key| !before.contains(key))
        .collect();
    injected.sort();

    println!("injected {} secret(s):", result.injected);
    for key in &injected {
        let value = env::var(key).unwrap_or_default();
        println!("  env     {key} = {value}");
    }

    if injected.is_empty() {
        println!("  (the project has no secrets in this environment)");
    }
}
