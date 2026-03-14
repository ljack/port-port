import Foundation

/// Detects the technology stack from a process executable path and arguments
public enum TechStackDetector: Sendable {
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
            let a = arg.lowercased()
            if a.hasSuffix(".js") || a.hasSuffix(".mjs") || a.hasSuffix(".cjs") || a.contains("next") || a.contains("vite") || a.contains("webpack") {
                return .nodeJS
            }
            if a.hasSuffix(".py") || a.contains("django") || a.contains("flask") || a.contains("fastapi") {
                return .python
            }
            if a.hasSuffix(".rb") {
                return .ruby
            }
            if a.hasSuffix(".jar") {
                return .java
            }
            if a.hasSuffix(".ts") && !a.contains("node") {
                // TypeScript files run via Deno or Bun
                if lowered.contains("deno") { return .deno }
                if lowered.contains("bun") { return .bun }
                return .nodeJS
            }
        }

        return .unknown
    }
}
