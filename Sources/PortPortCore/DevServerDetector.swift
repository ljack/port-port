import Foundation

/// Detects whether a port listener is likely a development server
public enum DevServerDetector {
    public static let home = FileManager.default.homeDirectoryForCurrentUser.path()

    /// Executable names that are always dev servers regardless of context
    private static let devExecutables: Set<String> = [
        "node", "nodejs", "deno", "bun",
        "python", "python3", "uvicorn", "gunicorn",
        "ruby", "puma", "rails", "thin",
        "java", "gradle", "mvn",
        "beam.smp", "elixir", "erl", "iex",
        "dotnet",
        "php", "php-fpm",
        "nodemon", "tsx", "ts-node", "npx",
        "cargo",
    ]

    /// Args that strongly indicate a dev server (specific enough to avoid false positives)
    private static let devArgPatterns: [String] = [
        "vite", "webpack", "next dev", "next start", "nuxt", "remix", "astro",
        "uvicorn", "gunicorn", "flask run", "django", "fastapi",
        "spring-boot", "bootrun",
        "rails server", "rails s",
        "nodemon", "tsx watch", "ts-node",
        "cargo run", "cargo watch",
        "go run",
        "mix phx.server",
        "http.server", "simplehttpserver",
        "live-server", "lite-server", "browser-sync",
        "npm run dev", "npm start", "npm run start",
        "yarn dev", "yarn start",
        "pnpm dev", "pnpm start",
        "bun run", "bun dev",
        "deno run", "deno serve",
    ]

    /// Directories that indicate NOT a dev project (system/app paths under home)
    private static let nonDevDirPatterns: [String] = [
        "/Library/", "/Applications/", "/.Trash/",
        "/Google/", "/Dropbox/", "/OneDrive/",
        "/Containers/", "/Caches/", "/Logs/",
        "/.claude/", "/.npm/", "/.yarn/", "/.bun/",
        "/.cargo/", "/.rustup/", "/.local/",
        "/.nvm/", "/.volta/", "/.sdkman/",
        "/Downloads/",
    ]

    public static func isDev(_ listener: PortListener) -> Bool {
        isDev(
            techStack: listener.techStack,
            workingDirectory: listener.workingDirectory,
            commandArgs: listener.commandArgs,
            processPath: listener.processPath,
            processName: listener.processName
        )
    }

    public static func isDev(
        techStack: TechStack,
        workingDirectory: String,
        commandArgs: [String],
        processPath: String = "",
        processName: String = ""
    ) -> Bool {
        // Step 1: Check if the executable itself is a known dev runtime
        let execName = (processPath as NSString).lastPathComponent.lowercased()
        let isDevRuntime = devExecutables.contains(execName)

        // Step 2: Check if args contain specific dev server patterns
        let argsJoined = commandArgs.joined(separator: " ").lowercased()
        let hasDevArgs = devArgPatterns.contains { argsJoined.contains($0) }

        // Step 3: Check if working directory looks like a code project (under home, not a system path)
        let isProjectDir = isDevProjectDirectory(workingDirectory)

        // A dev runtime (node, python, etc.) in a project directory → dev server
        if isDevRuntime && isProjectDir { return true }

        // Specific dev args → dev server regardless of directory
        if hasDevArgs { return true }

        // Known tech stack + project directory → likely dev
        if techStack != .unknown && isProjectDir { return true }

        // Rust target dir or Go bin → dev server if in a project
        if isProjectDir {
            if processPath.contains("/target/debug/") || processPath.contains("/target/release/") {
                return true
            }
            if processPath.contains("/go/bin/") {
                return true
            }
        }

        return false
    }

    /// Check if a directory looks like a developer's project directory
    private static func isDevProjectDirectory(_ dir: String) -> Bool {
        guard !dir.isEmpty, dir != "/" else { return false }
        guard dir.hasPrefix(home) else { return false }

        // Exclude system/app directories under home
        for pattern in nonDevDirPatterns {
            if dir.contains(pattern) { return false }
        }

        return true
    }
}
