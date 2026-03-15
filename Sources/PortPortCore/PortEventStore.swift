import Foundation

/// Persists port events to disk with 30-day retention
public final class PortEventStore: Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private nonisolated(unsafe) var _events: [PortEventRecord] = []
    private static let maxAge: TimeInterval = 30 * 24 * 60 * 60  // 30 days
    private static let maxCount = 10_000

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("port-port", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("events.json")
        _events = Self.loadFromDisk(fileURL)
        pruneUnlocked()
    }

    public var events: [PortEventRecord] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }

    public func append(_ event: PortEventRecord) {
        lock.lock()
        _events.insert(event, at: 0)
        pruneUnlocked()
        let snapshot = _events
        lock.unlock()
        saveToDisk(snapshot)
    }

    public func remove(id: UUID) {
        lock.lock()
        _events.removeAll { $0.id == id }
        let snapshot = _events
        lock.unlock()
        saveToDisk(snapshot)
    }

    public func clearAll() {
        lock.lock()
        _events.removeAll()
        lock.unlock()
        saveToDisk([])
    }

    /// Must be called while lock is held
    private func pruneUnlocked() {
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        _events.removeAll { $0.timestamp < cutoff }
        if _events.count > Self.maxCount {
            _events = Array(_events.prefix(Self.maxCount))
        }
    }

    private static func loadFromDisk(_ fileURL: URL) -> [PortEventRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PortEventRecord].self, from: data)) ?? []
    }

    private func saveToDisk(_ snapshot: [PortEventRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
