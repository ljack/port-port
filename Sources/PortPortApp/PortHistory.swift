import Foundation
import PortPortCore

/// Persists port history to disk (MainActor wrapper for the app)
@MainActor
final class PortHistory {
    private let store = PortHistoryStore()

    var entries: [String: PortHistoryEntry] {
        store.entries
    }

    /// Update history from a live scan
    func update(from listeners: [PortListener]) {
        store.update(from: listeners)
    }

    /// Remove a history entry
    func remove(_ entry: PortHistoryEntry) {
        store.remove(entry)
    }

    /// Clear all history
    func clearAll() {
        store.clearAll()
    }
}
