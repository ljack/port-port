import Darwin
import Foundation
import PortPortCore

/// Represents a TUI event (start/stop notification)
struct TUIEvent {
    let date: Date
    let text: String
    let isStart: Bool
}

/// Pad a string to exactly `width` visible characters, truncating or padding as needed.
private func padVisible(_ str: String, _ width: Int) -> String {
    str.padding(toLength: width, withPad: " ", startingAt: 0)
}

/// Interactive TUI watch mode
final class TUI: @unchecked Sendable {
    private let scanner = PortScanner()
    private let history = PortHistoryStore()
    private let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt
    }()

    // State
    private var listeners: [PortListener] = []
    private var filtered: [PortListener] = []
    private var previousKeys: Set<String> = []
    private var pendingDepartures: [String: (listener: PortListener, at: Date)] = [:]
    private var events: [TUIEvent] = []
    private var selectedIndex = 0
    private var scrollOffset = 0
    private var isFirstScan = true
    private var running = true

    // Filters
    private var mineOnly = true
    private var devOnly = true
    private var gracePeriod: TimeInterval = 15.0

    private var previousListenerMap: [String: PortListener] = [:]

    func run() {
        Terminal.enableRawMode()
        Terminal.enterAlternateScreen()
        Terminal.hideCursor()
        installSignalHandlers()

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

    private func installSignalHandlers() {
        let cleanup: @convention(c) (Int32) -> Void = { _ in
            Terminal.showCursor(); Terminal.leaveAlternateScreen(); Terminal.disableRawMode(); exit(0)
        }
        signal(SIGINT, cleanup)
        signal(SIGTERM, cleanup)
        signal(SIGWINCH) { _ in }
    }

    private func scanWithDepartures() {
        listeners = scanner.scan()
        history.update(from: listeners)

        let currentMap = Dictionary(
            listeners.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let currentKeys = Set(currentMap.keys)

        if !isFirstScan {
            detectArrivalsAndDepartures(currentMap: currentMap, currentKeys: currentKeys)
        }

        previousKeys = currentKeys
        previousListenerMap = currentMap
        isFirstScan = false

        // Grace period check
        let now = Date()
        for (key, dep) in pendingDepartures where now.timeIntervalSince(dep.at) >= gracePeriod {
            pendingDepartures.removeValue(forKey: key)
            addEvent(
                "\(dep.listener.processName) stopped (was port \(dep.listener.port))",
                isStart: false
            )
        }

        applyFilters()
    }

    private func detectArrivalsAndDepartures(
        currentMap: [String: PortListener],
        currentKeys: Set<String>
    ) {
        let arrived = currentKeys.subtracting(previousKeys)
        for key in arrived {
            if pendingDepartures.removeValue(forKey: key) != nil { continue }
            guard let listener = currentMap[key], matchesFilters(listener) else { continue }
            addEvent("\(listener.processName) started on port \(listener.port)", isStart: true)
        }

        let departed = previousKeys.subtracting(currentKeys)
        for key in departed {
            guard let listener = previousListenerMap[key], matchesFilters(listener) else { continue }
            pendingDepartures[key] = (listener, Date())
        }
    }

    private func matchesFilters(_ listener: PortListener) -> Bool {
        if mineOnly && listener.uid != getuid() { return false }
        if devOnly && !DevServerDetector.isDev(listener) { return false }
        return true
    }

    private func applyFilters() {
        filtered = DevFilter.filter(listeners, mine: mineOnly, dev: devOnly)
        if selectedIndex >= filtered.count {
            selectedIndex = max(0, filtered.count - 1)
        }
    }

    private func addEvent(_ text: String, isStart: Bool) {
        events.insert(TUIEvent(date: Date(), text: text, isStart: isStart), at: 0)
        if events.count > 50 { events.removeLast() }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func handleKey(_ key: Terminal.Key) {
        switch key {
        case .char("q"), .char("Q"):
            running = false
        case .char("j"), .down:
            if selectedIndex < filtered.count - 1 { selectedIndex += 1 }
        case .char("k"), .arrowUp:
            if selectedIndex > 0 { selectedIndex -= 1 }
        case .char("m"), .char("M"):
            mineOnly.toggle(); applyFilters()
        case .char("d"), .char("D"):
            devOnly.toggle(); applyFilters()
        case .char("x"), .char("X"):
            killSelected(force: false)
        case .char("K"):
            killSelected(force: true)
        case .char("o"), .char("O"):
            openBrowser()
        case .char("t"), .char("T"):
            openTerminal()
        case .char("r"), .char("R"):
            scanWithDepartures()
        case .escape:
            break
        default:
            break
        }
    }

    private func killSelected(force: Bool) {
        guard selectedIndex < filtered.count else { return }
        let listener = filtered[selectedIndex]
        kill(listener.pid, force ? SIGKILL : SIGTERM)
        addEvent(
            "Sent \(force ? "SIGKILL" : "SIGTERM") to \(listener.processName) (PID \(listener.pid))",
            isStart: false
        )
        usleep(500_000)
        scanWithDepartures()
    }

    private func openBrowser() {
        guard selectedIndex < filtered.count else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["http://localhost:\(filtered[selectedIndex].port)"]
        try? process.run()
    }

    private func openTerminal() {
        guard selectedIndex < filtered.count else { return }
        let cwd = filtered[selectedIndex].workingDirectory
        guard !cwd.isEmpty else { return }
        let escaped = cwd.replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Terminal\" to do script \"cd \(escaped)\""]
        try? process.run()
    }

    // MARK: - Rendering

    private func render() {
        let (rows, cols) = Terminal.size()
        var buf = "\u{1b}[H"
        let sep = Terminal.dim(String(repeating: "\u{2500}", count: cols))
        buf += renderHeader(cols: cols, separator: sep)
        buf += renderPortList(rows: rows, cols: cols)
        buf += renderEvents(separator: sep)
        buf += renderHelpBar(separator: sep)
        Terminal.flush(buf)
    }

    private func renderHeader(cols: Int, separator: String) -> String {
        let mineTag = mineOnly ? Terminal.bgBlue(" Mine ") : Terminal.dim(" Mine ")
        let devTag = devOnly ? Terminal.bgBlue(" Dev ") : Terminal.dim(" Dev ")
        let graceTag = Terminal.dim(" Grace:\(Int(gracePeriod))s ")
        let countStr = Terminal.bold("\(filtered.count)") + Terminal.dim(" ports")
        let header = " port-port  \(mineTag) \(devTag) \(graceTag)  \(countStr)"
        let colHeader = "  "
            + padVisible("PORT", 7) + " " + padVisible("PROTO", 5) + " "
            + padVisible("TECH", 8) + " " + padVisible("UPTIME", 8) + " "
            + padVisible("COMMAND", 40) + " " + "DIRECTORY"
        return "\u{1b}[2K" + header + "\n"
            + "\u{1b}[2K" + separator + "\n"
            + "\u{1b}[2K" + Terminal.dim(colHeader) + "\n"
    }

    private func renderPortList(rows: Int, cols: Int) -> String {
        let fixedW = 2 + 7 + 1 + 5 + 1 + 8 + 1 + 8 + 1 + 40 + 1
        let dirW = max(10, cols - fixedW)
        var buf = ""
        let listHeight = rows - 7 - min(events.count, 4)
        if selectedIndex < scrollOffset { scrollOffset = selectedIndex }
        if selectedIndex >= scrollOffset + listHeight { scrollOffset = selectedIndex - listHeight + 1 }

        for idx in 0..<listHeight {
            buf += "\u{1b}[2K"
            let rowIndex = scrollOffset + idx
            if rowIndex < filtered.count {
                buf += renderPortRow(
                    filtered[rowIndex], selected: rowIndex == selectedIndex,
                    dirW: dirW, cols: cols, fixedW: fixedW
                )
            }
            buf += "\n"
        }
        return buf
    }

    private func renderPortRow(_ listener: PortListener, selected: Bool, dirW: Int, cols: Int, fixedW: Int) -> String {
        let cwd = PathUtils.abbreviate(listener.workingDirectory)
        let techRaw = Formatter.techPlain(listener.techStack)
        let cwdStr = String(cwd.prefix(dirW))
        let content = "\(Terminal.green("\u{25CF}")) "
            + "\(padVisible(String(listener.port), 7)) "
            + "\(padVisible(listener.protocol.rawValue, 5)) "
            + "\(Formatter.techBadge(listener.techStack))\(String(repeating: " ", count: max(0, 8 - techRaw.count))) "
            + "\(padVisible(Formatter.formatUptime(listener.startTime), 8)) "
            + "\(padVisible(String(listener.command.prefix(40)), 40)) "
            + Terminal.dim(cwdStr)
        let trailingPad = max(0, cols - fixedW - cwdStr.count)
        return selected
            ? Terminal.inverse(content + String(repeating: " ", count: trailingPad))
            : content
    }

    private func renderEvents(separator: String) -> String {
        var buf = "\u{1b}[2K" + separator + "\n"
        let eventCount = min(events.count, 3)
        if eventCount > 0 {
            for idx in 0..<eventCount {
                let event = events[idx]
                let icon = event.isStart ? Terminal.green("\u{25B2}") : Terminal.yellow("\u{25BC}")
                buf += "\u{1b}[2K \(icon) \(Terminal.dim(timeFormatter.string(from: event.date))) \(event.text)\n"
            }
        } else {
            buf += "\u{1b}[2K" + Terminal.dim(" No events yet") + "\n"
        }
        return buf
    }

    private func renderHelpBar(separator: String) -> String {
        "\u{1b}[2K" + separator + "\n\u{1b}[2K"
            + " \(Terminal.bold("j/k")) navigate  "
            + "\(Terminal.bold("x")) kill  "
            + "\(Terminal.bold("K")) force kill  "
            + "\(Terminal.bold("o")) browser  "
            + "\(Terminal.bold("t")) terminal  "
            + "\(Terminal.bold("m")) mine  "
            + "\(Terminal.bold("d")) dev  "
            + "\(Terminal.bold("r")) refresh  "
            + "\(Terminal.bold("q")) quit"
    }
}
