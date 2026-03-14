import Foundation
import PortPortCore

/// A remembered application that was seen listening on a port
struct PortHistoryEntry: Codable, Identifiable {
    /// Stable identity: hash of processPath + workingDirectory
    var id: String { "\(processPath):\(workingDirectory)" }

    var lastPort: UInt16
    var lastProtocol: TransportProtocol
    var processName: String
    var processPath: String
    var workingDirectory: String
    var techStack: TechStack
    var commandArgs: [String]
    var firstSeen: Date
    var lastSeen: Date

    init(from listener: PortListener) {
        self.lastPort = listener.port
        self.lastProtocol = listener.protocol
        self.processName = listener.processName
        self.processPath = listener.processPath
        self.workingDirectory = listener.workingDirectory
        self.techStack = listener.techStack
        self.commandArgs = listener.commandArgs
        self.firstSeen = Date()
        self.lastSeen = Date()
    }

    /// Update from a live listener
    mutating func update(from listener: PortListener) {
        lastPort = listener.port
        lastProtocol = listener.protocol
        processName = listener.processName
        commandArgs = listener.commandArgs
        techStack = listener.techStack
        lastSeen = Date()
    }
}

/// Persists port history to disk
@MainActor
final class PortHistory {
    private(set) var entries: [String: PortHistoryEntry] = [:]
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("port-port", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    /// Update history from a live scan
    func update(from listeners: [PortListener]) {
        for listener in listeners {
            // Skip system processes with no useful cwd
            guard !listener.processPath.isEmpty else { continue }
            guard !listener.workingDirectory.isEmpty || !listener.commandArgs.isEmpty else { continue }

            let key = "\(listener.processPath):\(listener.workingDirectory)"
            if var existing = entries[key] {
                existing.update(from: listener)
                entries[key] = existing
            } else {
                let entry = PortHistoryEntry(from: listener)
                entries[key] = entry
            }
        }
        save()
    }

    /// Remove a history entry
    func remove(_ entry: PortHistoryEntry) {
        entries.removeValue(forKey: entry.id)
        save()
    }

    /// Clear all history
    func clearAll() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([String: PortHistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
