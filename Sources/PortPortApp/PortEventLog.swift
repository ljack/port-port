import Foundation
import PortPortCore

/// MainActor wrapper for PortEventStore, observable for SwiftUI
@MainActor
@Observable
final class PortEventLog {
    private let store = PortEventStore()
    private var _events: [PortEventRecord] = []

    private struct ConflictKey: Hashable {
        let port: UInt16
        let originalProcess: String
        let conflictProcess: String
    }

    private var emittedConflicts: Set<ConflictKey> = []

    init() {
        _events = store.events
    }

    var events: [PortEventRecord] { _events }

    func append(_ event: PortEventRecord) {
        store.append(event)
        _events = store.events
    }

    func remove(id: UUID) {
        store.remove(id: id)
        _events = store.events
    }

    func clearAll() {
        store.clearAll()
        _events = store.events
        emittedConflicts.removeAll()
    }

    /// Returns true if this conflict hasn't been emitted yet
    func shouldEmitConflict(port: UInt16, originalProcess: String, conflictProcess: String) -> Bool {
        let key = ConflictKey(port: port, originalProcess: originalProcess, conflictProcess: conflictProcess)
        if emittedConflicts.contains(key) { return false }
        emittedConflicts.insert(key)
        return true
    }
}
