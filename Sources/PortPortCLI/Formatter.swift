import Foundation
import PortPortCore

/// Formats port data for CLI output
enum Formatter {
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

    static func techPlain(_ tech: TechStack) -> String {
        tech.rawValue
    }

    /// Format a table of listeners for terminal output
    static func table(_ listeners: [PortListener], color: Bool = true) -> String {
        guard !listeners.isEmpty else {
            return color ? Terminal.dim("No listening ports found.") : "No listening ports found."
        }

        var lines: [String] = []
        func pad(_ s: String, _ w: Int) -> String {
            s.padding(toLength: w, withPad: " ", startingAt: 0)
        }

        let header = "\(pad("PORT", 7)) \(pad("PROTO", 5)) \(pad("TECH", 8)) \(pad("UPTIME", 10)) \(pad("COMMAND", 30)) DIRECTORY"
        lines.append(color ? Terminal.bold(header) : header)

        for l in listeners {
            let cwd = PathUtils.abbreviate(l.workingDirectory)
            let port = pad(String(l.port), 7)
            let proto = pad(l.protocol.rawValue, 5)
            let techRaw = techPlain(l.techStack)
            let cmd = pad(String(l.command.prefix(30)), 30)
            let uptime = pad(formatUptime(l.startTime), 10)

            if color {
                let techStr = techBadge(l.techStack) + String(repeating: " ", count: max(0, 8 - techRaw.count))
                lines.append("\(Terminal.bold(port)) \(Terminal.dim(proto)) \(techStr) \(uptime) \(cmd) \(Terminal.dim(cwd))")
            } else {
                lines.append("\(port) \(proto) \(pad(techRaw, 8)) \(uptime) \(cmd) \(cwd)")
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
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        if h < 24 { return "\(h)h\(m)m" }
        return "\(h / 24)d\(h % 24)h"
    }
}
