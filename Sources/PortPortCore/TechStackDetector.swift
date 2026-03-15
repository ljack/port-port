import Foundation

/// Detects the technology stack from a process executable path and arguments
public enum TechStackDetector: Sendable {
    // swiftlint:disable:next cyclomatic_complexity
    public static func detect(path: String, args: [String] = []) -> TechStack {
        let lowered = path.lowercased()

        // Check executable name patterns
        if lowered.hasSuffix("/node") || lowered.contains("/node ") || lowered.contains("/nodejs") {
            return .nodeJS
        }
        if lowered.hasSuffix("/bun") || lowered.contains("/bun ") {
            return .bun
        }
        if lowered.hasSuffix("/deno") || lowered.contains("/deno ") {
            return .deno
        }
        if lowered.contains("/python") || lowered.contains("/uvicorn") || lowered.contains("/gunicorn") {
            return .python
        }
        if lowered.contains("/java") || lowered.contains("/gradle") || lowered.contains("/mvn") {
            return .java
        }
        if lowered.contains("/ruby") || lowered.contains("/puma") || lowered.contains("/rails") {
            return .ruby
        }
        if lowered.contains("/beam.smp") || lowered.contains("/elixir") || lowered.contains("/erl") {
            return .elixir
        }
        if lowered.contains("/dotnet") {
            return .dotnet
        }
        if lowered.contains("/php") || lowered.contains("/php-fpm") {
            return .php
        }

        // Go detection: Go binaries are typically statically linked
        // Check if it's in a typical Go path or GOPATH/bin
        if lowered.contains("/go/bin/") || lowered.contains("/gopath/") {
            return .go
        }

        // Rust detection: check for cargo target directories
        if lowered.contains("/target/debug/") || lowered.contains("/target/release/") {
            return .rust
        }

        // Check args for additional hints
        for arg in args {
            let lowArg = arg.lowercased()
            if let detected = detectFromArg(lowArg, pathLowered: lowered) {
                return detected
            }
        }

        return .unknown
    }

    private static func detectFromArg(_ lowArg: String, pathLowered: String) -> TechStack? {
        if lowArg.hasSuffix(".js") || lowArg.hasSuffix(".mjs") || lowArg.hasSuffix(".cjs")
            || lowArg.contains("next") || lowArg.contains("vite") || lowArg.contains("webpack") {
            return .nodeJS
        }
        if lowArg.hasSuffix(".py") || lowArg.contains("django")
            || lowArg.contains("flask") || lowArg.contains("fastapi") {
            return .python
        }
        if lowArg.hasSuffix(".rb") {
            return .ruby
        }
        if lowArg.hasSuffix(".jar") {
            return .java
        }
        if lowArg.hasSuffix(".ts") && !lowArg.contains("node") {
            // TypeScript files run via Deno or Bun
            if pathLowered.contains("deno") { return .deno }
            if pathLowered.contains("bun") { return .bun }
            return .nodeJS
        }
        return nil
    }
}
