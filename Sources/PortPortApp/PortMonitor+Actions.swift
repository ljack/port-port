import AppKit
import Foundation
import PortPortCore
import UserNotifications

// MARK: - Actions, Notifications, and Utilities

extension PortMonitor {

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
            let shellCmd = args.map {
                $0.contains(" ") ? "'\($0)'" : $0
            }.joined(separator: " ")
            let shell = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
            let escapedCwd = cwd.replacingOccurrences(of: " ", with: "\\ ")
            shell.arguments = ["-c", "cd \(escapedCwd) && \(shellCmd) &"]
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

    func openTerminal(at path: String) {
        guard !path.isEmpty else { return }
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
            tell application "Terminal"
                activate
                do script "cd \(escaped)"
            end tell
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    func openInBrowser(port: UInt16) {
        guard let url = URL(string: "http://localhost:\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - System Notifications

    var canSendNotifications: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func requestNotificationPermission() {
        guard canSendNotifications else { return }
        Task {
            try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    func sendSystemNotification(title: String, body: String) {
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

        NSApp.requestUserAttention(.informationalRequest)
    }

    func replacePort(in args: [String], old: UInt16, new: UInt16) -> [String] {
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
