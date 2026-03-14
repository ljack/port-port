import Darwin
import Foundation
import PortPortCore

/// Non-interactive CLI commands
enum Commands {

    static func list(mine: Bool, dev: Bool, tech: TechStack?, json: Bool) {
        let scanner = PortScanner()
        let results = DevFilter.filter(scanner.scan(), mine: mine, dev: dev, tech: tech)

        if json {
            if let output = try? Formatter.json(results) {
                print(output)
            }
        } else {
            print(Formatter.table(results))
        }
    }

    static func info(port: UInt16, json: Bool) {
        let scanner = PortScanner()
        let results = scanner.scan()
        guard let listener = results.first(where: { $0.port == port }) else {
            fputs("No process listening on port \(port)\n", stderr)
            exit(1)
        }

        if json {
            if let output = try? Formatter.json([listener]) {
                print(output)
            }
            return
        }

        print(Terminal.bold("Port \(listener.port)") + " " + Terminal.dim(listener.protocol.rawValue))
        print("  Process:   \(listener.processName) (PID \(listener.pid))")
        print("  Command:   \(listener.command)")
        print("  Path:      \(listener.processPath)")
        print("  Directory: \(PathUtils.abbreviate(listener.workingDirectory))")
        print("  Tech:      \(Formatter.techBadge(listener.techStack))")
        print("  Uptime:    \(Formatter.formatUptime(listener.startTime))")
    }

    static func killPort(_ port: UInt16, force: Bool) {
        let scanner = PortScanner()
        let results = scanner.scan()
        let matches = results.filter { $0.port == port }

        guard !matches.isEmpty else {
            fputs("No process listening on port \(port)\n", stderr)
            exit(1)
        }

        let sig: Int32 = force ? SIGKILL : SIGTERM
        let sigName = force ? "SIGKILL" : "SIGTERM"
        let pids = Set(matches.map(\.pid))

        for pid in pids {
            let name = matches.first(where: { $0.pid == pid })?.processName ?? "unknown"
            kill(pid, sig)
            print("Sent \(sigName) to \(name) (PID \(pid))")
        }
    }

    static func history(json: Bool) {
        let hist = PortHistoryStore()
        let entries = hist.load()

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(entries),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
            return
        }

        guard !entries.isEmpty else {
            print(Terminal.dim("No history entries."))
            return
        }

        // Check which are currently running
        let scanner = PortScanner()
        let live = Set(scanner.scan().map { "\($0.processPath):\($0.workingDirectory)" })

        let header = String(format: "%-8s %-7s %-8s %-20s %-20s %s",
                           "STATUS", "PORT", "TECH", "PROCESS", "LAST SEEN", "DIRECTORY")
        print(Terminal.bold(header))

        let sorted = entries.sorted { $0.value.lastSeen > $1.value.lastSeen }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated

        for (key, entry) in sorted {
            let running = live.contains(key)
            let status = running ? Terminal.green("● live") : Terminal.gray("○ stop")
            let port = String(entry.lastPort).padding(toLength: 7, withPad: " ", startingAt: 0)
            let tech = Formatter.techPlain(entry.techStack).padding(toLength: 8, withPad: " ", startingAt: 0)
            let name = String(entry.processName.prefix(20)).padding(toLength: 20, withPad: " ", startingAt: 0)
            let ago = formatter.localizedString(for: entry.lastSeen, relativeTo: Date())
                .padding(toLength: 20, withPad: " ", startingAt: 0)
            let cwd = PathUtils.abbreviate(entry.workingDirectory)

            print("\(status)  \(port) \(tech) \(name) \(Terminal.dim(ago)) \(Terminal.dim(cwd))")
        }
    }

    static func restart(port: UInt16) {
        let hist = PortHistoryStore()
        let entries = hist.load()

        // Find history entry matching this port
        guard let (_, entry) = entries.first(where: { $0.value.lastPort == port }) else {
            fputs("No history entry for port \(port)\n", stderr)
            exit(1)
        }

        guard !entry.commandArgs.isEmpty else {
            fputs("No command args recorded for \(entry.processName)\n", stderr)
            exit(1)
        }

        // Check if port is taken
        let scanner = PortScanner()
        let live = scanner.scan()
        if let conflict = live.first(where: { $0.port == port }) {
            fputs("Port \(port) is in use by \(conflict.processName) (PID \(conflict.pid))\n", stderr)
            exit(1)
        }

        print("Restarting \(entry.processName) on port \(port)...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: entry.commandArgs[0])
        if entry.commandArgs.count > 1 {
            process.arguments = Array(entry.commandArgs.dropFirst())
        }
        if !entry.workingDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: entry.workingDirectory)
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            print(Terminal.green("Started \(entry.processName) (PID \(process.processIdentifier))"))
        } catch {
            fputs("Failed to start: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
