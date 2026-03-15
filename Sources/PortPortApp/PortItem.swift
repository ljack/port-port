import Foundation
import PortPortCore

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
        self.command = PortListener.formatCommand(
            args: historyEntry.commandArgs,
            processName: historyEntry.processName
        )
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

    init(fromEvent event: PortEventRecord, conflict: PortListener?) {
        self.id = "event:\(event.id.uuidString)"
        self.port = event.port
        self.protocol = .tcp
        self.pid = nil
        self.uid = 0
        self.processName = event.processName
        self.processPath = event.processPath
        self.workingDirectory = event.workingDirectory
        self.techStack = event.techStack
        self.commandArgs = event.commandArgs
        self.command = PortListener.formatCommand(
            args: event.commandArgs,
            processName: event.processName
        )
        self.startTime = nil
        self.status = .stopped
        self.lastSeen = event.timestamp
        self.portConflict = conflict
        self.isDev = DevServerDetector.isDev(
            techStack: event.techStack,
            workingDirectory: event.workingDirectory,
            commandArgs: event.commandArgs
        )
    }
}
