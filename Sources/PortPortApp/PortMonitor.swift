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
    let status: Status
    let lastSeen: Date?

    /// What's currently occupying this port, if anything (for stopped items)
    var portConflict: PortListener?

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

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
        self.status = .running(listener)
        self.lastSeen = nil
        self.portConflict = nil
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
        self.status = .stopped
        self.lastSeen = historyEntry.lastSeen
        self.portConflict = conflict
    }
}

@Observable
@MainActor
final class PortMonitor {
    var listeners: [PortListener] = []
    var items: [PortItem] = []
    var isScanning = false
    var lastScanTime: Date?
    var showHistory = true

    let history = PortHistory()
    private let scanner = PortScanner()
    private var scanTask: Task<Void, Never>?
    private var previousPorts: Set<String> = []

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

        let newPorts = Set(results.map(\.id))
        let addedPorts = newPorts.subtracting(previousPorts)

        if !previousPorts.isEmpty {
            let newListeners = results.filter { addedPorts.contains($0.id) }
            for listener in newListeners {
                sendNotification(for: listener)
            }
        }

        previousPorts = newPorts
        listeners = results

        // Update history with current scan
        history.update(from: results)

        // Build merged items list
        rebuildItems()

        lastScanTime = Date()
        isScanning = false
    }

    private func rebuildItems() {
        // Live listeners as items
        let liveKeys = Set(listeners.map { "\($0.processPath):\($0.workingDirectory)" })
        var result = listeners.map { PortItem(listener: $0) }

        // Add stopped history entries
        if showHistory {
            let portMap = Dictionary(grouping: listeners, by: \.port)
            for (key, entry) in history.entries {
                guard !liveKeys.contains(key) else { continue }
                let conflict = portMap[entry.lastPort]?.first
                result.append(PortItem(historyEntry: entry, conflict: conflict))
            }
        }

        result.sort { a, b in
            // Running items first, then by port
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

    /// Restart a stopped app from history
    func restartApp(_ item: PortItem, onPort: UInt16? = nil) {
        guard !item.commandArgs.isEmpty else { return }
        let args = item.commandArgs
        let cwd = item.workingDirectory

        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        if args.count > 1 {
            // If a custom port is requested, try to replace the port in args
            var processArgs = Array(args.dropFirst())
            if let port = onPort, port != item.port {
                processArgs = replacePort(in: processArgs, old: item.port, new: port)
            }
            process.arguments = processArgs
        }
        if !cwd.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        // Detach from our process group so it survives
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            // Scan after a short delay to pick it up
            Task {
                try? await Task.sleep(for: .seconds(1))
                await performScan()
            }
        } catch {
            // If direct exec fails, try via shell
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

    /// Find an available port near the preferred one
    func findAvailablePort(near preferred: UInt16) -> UInt16 {
        let usedPorts = Set(listeners.map(\.port))
        if !usedPorts.contains(preferred) { return preferred }
        // Try incrementing
        for offset in UInt16(1)...UInt16(100) {
            let candidate = preferred + offset
            if !usedPorts.contains(candidate) { return candidate }
        }
        return preferred + 1000
    }

    func removeHistoryEntry(_ item: PortItem) {
        let key = "\(item.processPath):\(item.workingDirectory)"
        if let entry = history.entries[key] {
            history.remove(entry)
            rebuildItems()
        }
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

    private var canSendNotifications: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private func requestNotificationPermission() {
        guard canSendNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(for listener: PortListener) {
        guard canSendNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = "New Port Listener"
        content.body = "\(listener.processName) started listening on port \(listener.port) (\(listener.techStack.rawValue))"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "port-\(listener.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Try to replace port number in command arguments
    private func replacePort(in args: [String], old: UInt16, new: UInt16) -> [String] {
        let oldStr = String(old)
        let newStr = String(new)
        return args.map { arg in
            if arg == oldStr { return newStr }
            if arg.contains(":\(oldStr)") {
                return arg.replacingOccurrences(of: ":\(oldStr)", with: ":\(newStr)")
            }
            // Handle --port=XXXX style
            if arg.contains("=\(oldStr)") {
                return arg.replacingOccurrences(of: "=\(oldStr)", with: "=\(newStr)")
            }
            return arg
        }
    }
}
