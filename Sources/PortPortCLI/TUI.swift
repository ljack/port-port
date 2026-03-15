import Darwin
import Foundation
import PortPortCore

/// Interactive TUI watch mode
final class TUI: @unchecked Sendable {
    private let scanner = PortScanner()
    private let history = PortHistoryStore()
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // State
    private var listeners: [PortListener] = []
    private var filtered: [PortListener] = []
    private var previousKeys: Set<String> = []
    private var pendingDepartures: [String: (listener: PortListener, at: Date)] = [:]
    private var events: [(date: Date, text: String, isStart: Bool)] = []
    private var selectedIndex = 0
    private var scrollOffset = 0
    private var isFirstScan = true
    private var running = true

    // Filters
    private var mineOnly = true
    private var devOnly = true
    private var gracePeriod: TimeInterval = 15.0

    func run() {
        Terminal.enableRawMode()
        Terminal.enterAlternateScreen()
        Terminal.hideCursor()

        // Handle SIGINT/SIGTERM gracefully
        signal(SIGINT) { _ in
            Terminal.showCursor()
            Terminal.leaveAlternateScreen()
            Terminal.disableRawMode()
            exit(0)
        }
        signal(SIGTERM) { _ in
            Terminal.showCursor()
            Terminal.leaveAlternateScreen()
            Terminal.disableRawMode()
            exit(0)
        }

        // Handle SIGWINCH (terminal resize)
        signal(SIGWINCH) { _ in }

        while running {
            scanWithDepartures()
            render()

            // Poll for input for ~2 seconds (in 100ms chunks)
            for _ in 0..<20 {
                guard running else { break }
                if let key = Terminal.readKey() {
                    handleKey(key)
                    render()
                }
            }
        }

        Terminal.showCursor()
        Terminal.leaveAlternateScreen()
        Terminal.disableRawMode()
    }

    private var previousListenerMap: [String: PortListener] = [:]

    private func scanWithDepartures() {
        listeners = scanner.scan()
        history.update(from: listeners)

        let currentMap = Dictionary(listeners.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let currentKeys = Set(currentMap.keys)

        if !isFirstScan {
            let arrived = currentKeys.subtracting(previousKeys)
            for key in arrived {
                if pendingDepartures.removeValue(forKey: key) != nil { continue }
                guard let l = currentMap[key], matchesFilters(l) else { continue }
                addEvent("\(l.processName) started on port \(l.port)", isStart: true)
            }

            let departed = previousKeys.subtracting(currentKeys)
            for key in departed {
                guard let l = previousListenerMap[key], matchesFilters(l) else { continue }
                pendingDepartures[key] = (l, Date())
            }
        }

        previousKeys = currentKeys
        previousListenerMap = currentMap
        isFirstScan = false

        // Grace period check
        let now = Date()
        for (key, dep) in pendingDepartures {
            if now.timeIntervalSince(dep.at) >= gracePeriod {
                pendingDepartures.removeValue(forKey: key)
                addEvent("\(dep.listener.processName) stopped (was port \(dep.listener.port))", isStart: false)
            }
        }

        applyFilters()
    }

    private func matchesFilters(_ l: PortListener) -> Bool {
        if mineOnly && l.uid != getuid() { return false }
        if devOnly && !DevServerDetector.isDev(l) { return false }
        return true
    }

    private func applyFilters() {
        filtered = DevFilter.filter(listeners, mine: mineOnly, dev: devOnly)
        if selectedIndex >= filtered.count {
            selectedIndex = max(0, filtered.count - 1)
        }
    }

    private func addEvent(_ text: String, isStart: Bool) {
        events.insert((Date(), text, isStart), at: 0)
        if events.count > 50 { events.removeLast() }
    }

    private func handleKey(_ key: Terminal.Key) {
        switch key {
        case .char("q"), .char("Q"):
            running = false
        case .char("j"), .down:
            if selectedIndex < filtered.count - 1 { selectedIndex += 1 }
        case .char("k"), .up:
            if selectedIndex > 0 { selectedIndex -= 1 }
        case .char("m"), .char("M"):
            mineOnly.toggle()
            applyFilters()
        case .char("d"), .char("D"):
            devOnly.toggle()
            applyFilters()
        case .char("x"), .char("X"):
            killSelected(force: false)
        case .char("K"):
            killSelected(force: true)
        case .char("o"), .char("O"):
            openBrowser()
        case .char("t"), .char("T"):
            openTerminal()
        case .char("r"), .char("R"):
            refresh()
        case .escape:
            break
        default:
            break
        }
    }

    private func killSelected(force: Bool) {
        guard selectedIndex < filtered.count else { return }
        let l = filtered[selectedIndex]
        let sig: Int32 = force ? SIGKILL : SIGTERM
        kill(l.pid, sig)
        addEvent("Sent \(force ? "SIGKILL" : "SIGTERM") to \(l.processName) (PID \(l.pid))", isStart: false)
        usleep(500_000)
        scanWithDepartures()
    }

    private func openBrowser() {
        guard selectedIndex < filtered.count else { return }
        let port = filtered[selectedIndex].port
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["http://localhost:\(port)"]
        try? process.run()
    }

    private func openTerminal() {
        guard selectedIndex < filtered.count else { return }
        let cwd = filtered[selectedIndex].workingDirectory
        guard !cwd.isEmpty else { return }
        let script = "tell application \"Terminal\" to do script \"cd \(cwd.replacingOccurrences(of: "\"", with: "\\\""))\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    private func refresh() {
        scanWithDepartures()
    }

    // MARK: - Rendering

    /// Pad a string to exactly `width` visible characters, truncating or padding as needed.
    /// ANSI escape codes are not counted toward width.
    private func padVisible(_ s: String, _ width: Int) -> String {
        s.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    private func render() {
        let (rows, cols) = Terminal.size()
        var buf = ""
        let sep = Terminal.dim(String(repeating: "─", count: cols))

        buf += "\u{1b}[H" // Move to top-left

        // Header (row 1)
        let mineTag = mineOnly ? Terminal.bgBlue(" Mine ") : Terminal.dim(" Mine ")
        let devTag = devOnly ? Terminal.bgBlue(" Dev ") : Terminal.dim(" Dev ")
        let graceTag = Terminal.dim(" Grace:\(Int(gracePeriod))s ")
        let countStr = Terminal.bold("\(filtered.count)") + Terminal.dim(" ports")
        let header = " port-port  \(mineTag) \(devTag) \(graceTag)  \(countStr)"
        buf += "\u{1b}[2K" + header + "\n"

        // Separator
        buf += "\u{1b}[2K" + sep + "\n"

        // Fixed column widths (visible chars)
        let prefixW = 2   // "● " or "  "
        let portW = 7
        let protoW = 5
        let techW = 8
        let uptimeW = 8
        let cmdW = 40
        let fixedW = prefixW + portW + 1 + protoW + 1 + techW + 1 + uptimeW + 1 + cmdW + 1  // separating spaces
        let dirW = max(10, cols - fixedW)

        // Column headers (row 3)
        let colHeader = "  "
            + padVisible("PORT", portW) + " "
            + padVisible("PROTO", protoW) + " "
            + padVisible("TECH", techW) + " "
            + padVisible("UPTIME", uptimeW) + " "
            + padVisible("COMMAND", cmdW) + " "
            + "DIRECTORY"
        buf += "\u{1b}[2K" + Terminal.dim(colHeader) + "\n"

        // Port list
        let listHeight = rows - 7 - min(events.count, 4)
        if selectedIndex < scrollOffset { scrollOffset = selectedIndex }
        if selectedIndex >= scrollOffset + listHeight { scrollOffset = selectedIndex - listHeight + 1 }

        for i in 0..<listHeight {
            buf += "\u{1b}[2K"
            let idx = scrollOffset + i
            if idx < filtered.count {
                let l = filtered[idx]
                let selected = idx == selectedIndex
                let cwd = PathUtils.abbreviate(l.workingDirectory)

                let dot = Terminal.green("●")
                let port = padVisible(String(l.port), portW)
                let proto = padVisible(l.protocol.rawValue, protoW)
                let techRaw = Formatter.techPlain(l.techStack)
                let tech = Formatter.techBadge(l.techStack) + String(repeating: " ", count: max(0, techW - techRaw.count))
                let uptime = padVisible(Formatter.formatUptime(l.startTime), uptimeW)
                let cmd = padVisible(String(l.command.prefix(cmdW)), cmdW)
                let cwdStr = String(cwd.prefix(dirW))

                // Build the content part (visible width = fixedW + cwd visible length)
                let content = "\(dot) \(port) \(proto) \(tech) \(uptime) \(cmd) \(Terminal.dim(cwdStr))"
                // Pad the line to full terminal width for consistent highlight
                let cwdVisible = cwdStr.count
                let trailingPad = max(0, cols - fixedW - cwdVisible)

                if selected {
                    buf += Terminal.inverse(content + String(repeating: " ", count: trailingPad))
                } else {
                    buf += content
                }
            }
            buf += "\n"
        }

        // Events section
        buf += "\u{1b}[2K" + sep + "\n"
        let eventCount = min(events.count, 3)
        if eventCount > 0 {
            for i in 0..<eventCount {
                buf += "\u{1b}[2K"
                let e = events[i]
                let timeStr = formatTime(e.date)
                let icon = e.isStart ? Terminal.green("▲") : Terminal.yellow("▼")
                buf += " \(icon) \(Terminal.dim(timeStr)) \(e.text)\n"
            }
        } else {
            buf += "\u{1b}[2K" + Terminal.dim(" No events yet") + "\n"
        }

        // Help bar
        buf += "\u{1b}[2K" + sep + "\n"
        buf += "\u{1b}[2K"
        let help = " \(Terminal.bold("j/k")) navigate  "
            + "\(Terminal.bold("x")) kill  "
            + "\(Terminal.bold("K")) force kill  "
            + "\(Terminal.bold("o")) browser  "
            + "\(Terminal.bold("t")) terminal  "
            + "\(Terminal.bold("m")) mine  "
            + "\(Terminal.bold("d")) dev  "
            + "\(Terminal.bold("r")) refresh  "
            + "\(Terminal.bold("q")) quit"
        buf += help

        Terminal.flush(buf)
    }

    private func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}
