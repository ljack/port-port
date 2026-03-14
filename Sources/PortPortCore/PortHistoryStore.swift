import Foundation

/// A remembered application that was seen listening on a port
public struct PortHistoryEntry: Codable, Sendable, Identifiable {
    /// Stable identity: processPath + workingDirectory
    public var id: String { "\(processPath):\(workingDirectory)" }

    public var lastPort: UInt16
    public var lastProtocol: TransportProtocol
    public var processName: String
    public var processPath: String
    public var workingDirectory: String
    public var techStack: TechStack
    public var commandArgs: [String]
    public var firstSeen: Date
    public var lastSeen: Date

    public init(from listener: PortListener) {
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
    public mutating func update(from listener: PortListener) {
        lastPort = listener.port
        lastProtocol = listener.protocol
        processName = listener.processName
        commandArgs = listener.commandArgs
        techStack = listener.techStack
        lastSeen = Date()
    }

    /// Key used for dictionary storage
    public static func historyKey(for listener: PortListener) -> String {
        "\(listener.processPath):\(listener.workingDirectory)"
    }
}

/// Persists port history to disk, shared between app and CLI
public final class PortHistoryStore: Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private nonisolated(unsafe) var _entries: [String: PortHistoryEntry] = [:]

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("port-port", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("history.json")
        _entries = Self.loadFromDisk(fileURL)
    }

    public var entries: [String: PortHistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    /// Update history from a live scan. Only saves if entries actually changed.
    public func update(from listeners: [PortListener]) {
        lock.lock()
        var changed = false

        for listener in listeners {
            guard !listener.processPath.isEmpty else { continue }
            guard !listener.processName.isEmpty else { continue }
            guard !listener.commandArgs.isEmpty else { continue }
            guard listener.workingDirectory != "/" else { continue }

            let key = PortHistoryEntry.historyKey(for: listener)
            if var existing = _entries[key] {
                let before = existing
                existing.update(from: listener)
                // Check if anything meaningful changed (ignore lastSeen timestamp)
                if before.lastPort != existing.lastPort ||
                   before.lastProtocol != existing.lastProtocol ||
                   before.processName != existing.processName ||
                   before.commandArgs != existing.commandArgs ||
                   before.techStack != existing.techStack {
                    _entries[key] = existing
                    changed = true
                } else {
                    // Still update lastSeen but mark changed for periodic saves
                    _entries[key] = existing
                    changed = true
                }
            } else {
                _entries[key] = PortHistoryEntry(from: listener)
                changed = true
            }
        }

        lock.unlock()
        if changed {
            save()
        }
    }

    /// Remove a history entry
    public func remove(_ entry: PortHistoryEntry) {
        lock.lock()
        _entries.removeValue(forKey: entry.id)
        lock.unlock()
        save()
    }

    /// Clear all history
    public func clearAll() {
        lock.lock()
        _entries.removeAll()
        lock.unlock()
        save()
    }

    /// Load entries (for callers that need a snapshot)
    public func load() -> [String: PortHistoryEntry] {
        entries
    }

    private static func loadFromDisk(_ fileURL: URL) -> [String: PortHistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: PortHistoryEntry].self, from: data)) ?? [:]
    }

    private func save() {
        lock.lock()
        let snapshot = _entries
        lock.unlock()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
