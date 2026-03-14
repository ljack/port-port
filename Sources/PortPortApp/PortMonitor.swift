import AppKit
import Foundation
import PortPortCore
import UserNotifications

/// Represents an item in the unified port list (live or from history)
struct PortItem: Identifiable {
    enum Status {
        case running(PortListener)
        case stopped
    }

    let id: String
    let port: UInt16
    let `protocol`: TransportProtocol
    let pid: Int32?
    let uid: UInt32
    let processName: String
    let processPath: String
    let workingDirectory: String
    let techStack: TechStack
    let commandArgs: [String]
    let command: String
    let startTime: Date?
    let status: Status
    let lastSeen: Date?

    /// What's currently occupying this port, if anything (for stopped items)
    var portConflict: PortListener?

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    /// Heuristic: is this likely a development server? Computed once at init.
    let isDev: Bool

    /// History key: matches PortHistoryEntry.id format
    var historyKey: String { "\(processPath):\(workingDirectory)" }

    init(listener: PortListener) {
        self.id = listener.id
        self.port = listener.port
        self.protocol = listener.protocol
        self.pid = listener.pid
        self.uid = listener.uid
        self.processName = listener.processName
        self.processPath = listener.processPath
        self.workingDirectory = listener.workingDirectory
        self.techStack = listener.techStack
        self.commandArgs = listener.commandArgs
        self.command = listener.command
        self.startTime = listener.startTime
        self.status = .running(listener)
        self.lastSeen = nil
        self.portConflict = nil
        self.isDev = DevServerDetector.isDev(listener)
    }

    init(historyEntry: PortHistoryEntry, conflict: PortListener?) {
        self.id = "history:\(historyEntry.id)"
        self.port = historyEntry.lastPort
        self.protocol = historyEntry.lastProtocol
        self.pid = nil
        self.uid = 0
        self.processName = historyEntry.processName
        self.processPath = historyEntry.processPath
        self.workingDirectory = historyEntry.workingDirectory
        self.techStack = historyEntry.techStack
        self.commandArgs = historyEntry.commandArgs
        self.command = historyEntry.commandArgs.isEmpty
            ? historyEntry.processName
            : ([((historyEntry.commandArgs[0] as NSString).lastPathComponent)] + historyEntry.commandArgs.dropFirst()).joined(separator: " ")
        self.startTime = nil
        self.status = .stopped
        self.lastSeen = historyEntry.lastSeen
        self.portConflict = conflict
        self.isDev = DevServerDetector.isDev(
            techStack: historyEntry.techStack,
            workingDirectory: historyEntry.workingDirectory,
            commandArgs: historyEntry.commandArgs
        )
    }
}

/// Tracks a listener that disappeared, waiting for grace period before notifying
private struct PendingDeparture {
    let listener: PortListener
    let disappearedAt: Date
}

@Observable
@MainActor
final class PortMonitor {
    var listeners: [PortListener] = []
    var items: [PortItem] = []
    var isScanning = false
    var lastScanTime: Date?
    var showHistory = true

    // Filter state (shared with view so notifications respect filters)
    var myPortsOnly = true
    var devOnly = true

    // Notification settings
    var gracePeriod: TimeInterval = 15.0
    var notificationsEnabled = true

    // Event log
    var events: [PortEvent] = []
    /// Most recent event for toast display, auto-cleared
    var latestEvent: PortEvent?

    let history = PortHistory()
    private let scanner = PortScanner()
    private let currentUID = getuid()
    private let maxEvents = 100
    private var scanTask: Task<Void, Never>?
    private var previousListeners: [String: PortListener] = [:]  // keyed by listener.id
    private var pendingDepartures: [String: PendingDeparture] = [:]  // keyed by listener.id
    private var isFirstScan = true
    private var toastDismissTask: Task<Void, Never>?

    init() {
        startScanning()
        requestNotificationPermission()
    }

    nonisolated func cancel() {}

    func startScanning() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.performScan()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
    }

    func performScan() async {
        isScanning = true
        let results = await Task.detached(priority: .utility) { [scanner] in
            scanner.scan()
        }.value

        // Use first occurrence for duplicate IDs (same port on IPv4+IPv6)
        let currentMap = Dictionary(results.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currentKeys = Set(currentMap.keys)
        let previousKeys = Set(previousListeners.keys)

        if !isFirstScan {
            // Detect new arrivals
            let arrivedKeys = currentKeys.subtracting(previousKeys)
            for key in arrivedKeys {
                guard let listener = currentMap[key] else { continue }

                // If it was pending departure, it came back — cancel the departure
                if pendingDepartures.removeValue(forKey: key) != nil {
                    continue
                }

                if matchesNotificationFilters(listener) {
                    emitEvent(.started, for: listener)
                }
            }

            // Detect departures → add to pending
            let departedKeys = previousKeys.subtracting(currentKeys)
            for key in departedKeys {
                guard let listener = previousListeners[key] else { continue }
                // Only track if it matches filters
                if matchesNotificationFilters(listener) {
                    pendingDepartures[key] = PendingDeparture(
                        listener: listener,
                        disappearedAt: Date()
                    )
                }
            }

            // Check pending departures past grace period
            let now = Date()
            var confirmed: [String] = []
            for (key, pending) in pendingDepartures {
                if now.timeIntervalSince(pending.disappearedAt) >= gracePeriod {
                    confirmed.append(key)
                }
            }

            // Group confirmed departures by process name for notification grouping
            if !confirmed.isEmpty {
                var grouped: [String: [PendingDeparture]] = [:]
                for key in confirmed {
                    if let pending = pendingDepartures.removeValue(forKey: key) {
                        grouped[pending.listener.processName, default: []].append(pending)
                    }
                }
                for (_, departures) in grouped {
                    if departures.count > 1 {
                        // Grouped notification
                        let first = departures[0].listener
                        let count = departures.count
                        emitEvent(.stopped, title: "\(count) \(first.processName) processes stopped", port: 0, processName: "\(count)x \(first.processName)", techStack: first.techStack, workingDirectory: first.workingDirectory)
                    } else if let dep = departures.first {
                        emitEvent(.stopped, for: dep.listener)
                    }
                }
            }
        }

        isFirstScan = false
        previousListeners = currentMap
        listeners = results

        history.update(from: results)
        rebuildItems()

        lastScanTime = Date()
        isScanning = false
    }

    /// Check if a listener matches the current notification filters
    private func matchesNotificationFilters(_ listener: PortListener) -> Bool {
        if myPortsOnly && listener.uid != currentUID {
            return false
        }
        if devOnly && !DevServerDetector.isDev(listener) {
            return false
        }
        return true
    }

    private func emitEvent(_ kind: PortEvent.Kind, title: String, port: UInt16, processName: String, techStack: TechStack, workingDirectory: String) {
        guard notificationsEnabled else { return }

        let event = PortEvent(
            kind: kind,
            timestamp: Date(),
            port: port,
            processName: processName,
            techStack: techStack,
            workingDirectory: workingDirectory
        )
        events.insert(event, at: 0)
        if events.count > maxEvents { events = Array(events.prefix(maxEvents)) }

        latestEvent = event
        clearToastAfterDelay()

        sendSystemNotification(title: title, body: workingDirectory)
    }

    private func emitEvent(_ kind: PortEvent.Kind, for listener: PortListener) {
        let title: String = switch kind {
        case .started: "\(listener.processName) started on port \(listener.port)"
        case .stopped: "\(listener.processName) stopped (was port \(listener.port))"
        }
        emitEvent(kind, title: title, port: listener.port, processName: listener.processName, techStack: listener.techStack, workingDirectory: listener.workingDirectory)
    }

    private func clearToastAfterDelay() {
        toastDismissTask?.cancel()
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled {
                latestEvent = nil
            }
        }
    }

    private func rebuildItems() {
        let liveKeys = Set(listeners.map { PortHistoryEntry.historyKey(for: $0) })
        var result = listeners.map { PortItem(listener: $0) }

        if showHistory {
            let portMap = Dictionary(grouping: listeners, by: \.port)
            for (key, entry) in history.entries {
                guard !liveKeys.contains(key) else { continue }
                let conflict = portMap[entry.lastPort]?.first
                result.append(PortItem(historyEntry: entry, conflict: conflict))
            }
        }

        result.sort { a, b in
            if a.isRunning != b.isRunning { return a.isRunning }
            return a.port < b.port
        }

        items = result
    }

    func killProcess(pid: Int32, force: Bool = false) {
        let signal: Int32 = force ? SIGKILL : SIGTERM
        kill(pid, signal)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await performScan()
        }
    }

    func restartApp(_ item: PortItem, onPort: UInt16? = nil) {
        guard !item.commandArgs.isEmpty else { return }
        let args = item.commandArgs
        let cwd = item.workingDirectory

        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        if args.count > 1 {
            var processArgs = Array(args.dropFirst())
            if let port = onPort, port != item.port {
                processArgs = replacePort(in: processArgs, old: item.port, new: port)
            }
            process.arguments = processArgs
        }
        if !cwd.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            Task {
                try? await Task.sleep(for: .seconds(1))
                await performScan()
            }
        } catch {
            let shellCmd = args.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
            let shell = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
            shell.arguments = ["-c", "cd \(cwd.replacingOccurrences(of: " ", with: "\\ ")) && \(shellCmd) &"]
            shell.standardOutput = FileHandle.nullDevice
            shell.standardError = FileHandle.nullDevice
            try? shell.run()
            Task {
                try? await Task.sleep(for: .seconds(1))
                await performScan()
            }
        }
    }

    func findAvailablePort(near preferred: UInt16) -> UInt16 {
        let usedPorts = Set(listeners.map(\.port))
        if !usedPorts.contains(preferred) { return preferred }
        for offset in UInt16(1)...UInt16(100) {
            let candidate = preferred + offset
            if !usedPorts.contains(candidate) { return candidate }
        }
        return preferred + 1000
    }

    func removeHistoryEntry(_ item: PortItem) {
        let key = item.historyKey
        if let entry = history.entries[key] {
            history.remove(entry)
            rebuildItems()
        }
    }

    func clearEvents() {
        events.removeAll()
    }

    func openTerminal(at path: String) {
        guard !path.isEmpty else { return }
        let script = """
            tell application "Terminal"
                activate
                do script "cd \(path.replacingOccurrences(of: "\"", with: "\\\""))"
            end tell
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    func openInBrowser(port: UInt16) {
        let url = URL(string: "http://localhost:\(port)")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - System Notifications

    private var canSendNotifications: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private func requestNotificationPermission() {
        // AppDelegate handles this now, but keep as fallback
        guard canSendNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func sendSystemNotification(title: String, body: String) {
        guard canSendNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)

        // Also request attention (bounces dock icon / highlights in menu bar)
        NSApp.requestUserAttention(.informationalRequest)
    }

    private func replacePort(in args: [String], old: UInt16, new: UInt16) -> [String] {
        let oldStr = String(old)
        let newStr = String(new)
        return args.map { arg in
            if arg == oldStr { return newStr }
            if arg.contains(":\(oldStr)") {
                return arg.replacingOccurrences(of: ":\(oldStr)", with: ":\(newStr)")
            }
            if arg.contains("=\(oldStr)") {
                return arg.replacingOccurrences(of: "=\(oldStr)", with: "=\(newStr)")
            }
            return arg
        }
    }
}
