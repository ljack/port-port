import Foundation
import PortPortCore

/// Formats port data for CLI output
enum Formatter {
    // swiftlint:disable:next cyclomatic_complexity
    static func techBadge(_ tech: TechStack) -> String {
        switch tech {
        case .nodeJS: return Terminal.green("Node.js")
        case .python: return Terminal.blue("Python")
        case .java: return Terminal.yellow("Java")
        case .ruby: return Terminal.red("Ruby")
        case .go: return Terminal.cyan("Go")
        case .rust: return Terminal.yellow("Rust")
        case .deno: return Terminal.green("Deno")
        case .bun: return Terminal.magenta("Bun")
        case .elixir: return Terminal.magenta("Elixir")
        case .dotnet: return Terminal.blue(".NET")
        case .php: return Terminal.cyan("PHP")
        case .unknown: return Terminal.gray("???")
        }
    }

    /// The visible (non-ANSI) text shown by techBadge
    static func techPlain(_ tech: TechStack) -> String { // swiftlint:disable:this cyclomatic_complexity
        switch tech {
        case .nodeJS: "Node.js"
        case .python: "Python"
        case .java: "Java"
        case .ruby: "Ruby"
        case .go: "Go"
        case .rust: "Rust"
        case .deno: "Deno"
        case .bun: "Bun"
        case .elixir: "Elixir"
        case .dotnet: ".NET"
        case .php: "PHP"
        case .unknown: "???"
        }
    }

    /// Format a table of listeners for terminal output
    static func table(_ listeners: [PortListener], color: Bool = true) -> String {
        guard !listeners.isEmpty else {
            return color ? Terminal.dim("No listening ports found.") : "No listening ports found."
        }

        var lines: [String] = []
        func pad(_ str: String, _ width: Int) -> String {
            str.padding(toLength: width, withPad: " ", startingAt: 0)
        }

        let header = "\(pad("PORT", 7)) \(pad("PROTO", 5)) \(pad("TECH", 8)) "
            + "\(pad("UPTIME", 10)) \(pad("COMMAND", 40)) DIRECTORY"
        lines.append(color ? Terminal.bold(header) : header)

        for listener in listeners {
            let cwd = PathUtils.abbreviate(listener.workingDirectory)
            let port = pad(String(listener.port), 7)
            let proto = pad(listener.protocol.rawValue, 5)
            let techRaw = techPlain(listener.techStack)
            let cmd = pad(String(listener.command.prefix(40)), 40)
            let uptime = pad(formatUptime(listener.startTime), 10)

            if color {
                let techStr = techBadge(listener.techStack)
                    + String(repeating: " ", count: max(0, 8 - techRaw.count))
                lines.append(
                    "\(Terminal.bold(port)) \(Terminal.dim(proto)) "
                    + "\(techStr) \(uptime) \(cmd) \(Terminal.dim(cwd))"
                )
            } else {
                lines.append(
                    "\(port) \(proto) \(pad(techRaw, 8)) \(uptime) \(cmd) \(cwd)"
                )
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Format as JSON
    static func json(_ listeners: [PortListener]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(listeners)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func formatUptime(_ startTime: Date?) -> String {
        guard let start = startTime else { return "?" }
        let elapsed = Int(Date().timeIntervalSince(start))
        if elapsed < 60 { return "\(elapsed)s" }
        if elapsed < 3600 { return "\(elapsed / 60)m\(elapsed % 60)s" }
        let hours = elapsed / 3600
        let mins = (elapsed % 3600) / 60
        if hours < 24 { return "\(hours)h\(mins)m" }
        return "\(hours / 24)d\(hours % 24)h"
    }
}
