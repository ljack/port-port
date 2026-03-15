import AppKit
import Foundation
import PortPortCore
import UserNotifications

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

    let eventLog: PortEventLog
    let history = PortHistory()
    private let scanner = PortScanner()
    private let currentUID = getuid()
    private let maxEvents = 100
    private var scanTask: Task<Void, Never>?
    private var previousListeners: [String: PortListener] = [:]
    private var pendingDepartures: [String: PendingDeparture] = [:]
    private var isFirstScan = true
    private var toastDismissTask: Task<Void, Never>?

    init(eventLog: PortEventLog) {
        self.eventLog = eventLog
        startScanning()
        requestNotificationPermission()
    }

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

        let currentMap = Dictionary(
            results.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let currentKeys = Set(currentMap.keys)
        let previousKeys = Set(previousListeners.keys)

        if !isFirstScan {
            detectArrivals(currentKeys: currentKeys, previousKeys: previousKeys, currentMap: currentMap)
            detectDepartures(currentKeys: currentKeys, previousKeys: previousKeys)
            processGracePeriodDepartures()
        }

        isFirstScan = false
        previousListeners = currentMap
        listeners = results

        history.update(from: results)
        rebuildItems()

        lastScanTime = Date()
        isScanning = false
    }

    // MARK: - Scan Helpers

    private func detectArrivals(
        currentKeys: Set<String>,
        previousKeys: Set<String>,
        currentMap: [String: PortListener]
    ) {
        let arrivedKeys = currentKeys.subtracting(previousKeys)
        for key in arrivedKeys {
            guard let listener = currentMap[key] else { continue }

            if pendingDepartures.removeValue(forKey: key) != nil {
                continue
            }

            if matchesNotificationFilters(listener) {
                emitEvent(.started, for: listener)
            }
        }
    }

    private func detectDepartures(
        currentKeys: Set<String>,
        previousKeys: Set<String>
    ) {
        let departedKeys = previousKeys.subtracting(currentKeys)
        for key in departedKeys {
            guard let listener = previousListeners[key] else { continue }
            if matchesNotificationFilters(listener) {
                pendingDepartures[key] = PendingDeparture(
                    listener: listener,
                    disappearedAt: Date()
                )
            }
        }
    }

    private func processGracePeriodDepartures() {
        let now = Date()
        var confirmed: [String] = []
        for (key, pending) in pendingDepartures
            where now.timeIntervalSince(pending.disappearedAt) >= gracePeriod {
            confirmed.append(key)
        }

        guard !confirmed.isEmpty else { return }

        var grouped: [String: [PendingDeparture]] = [:]
        for key in confirmed {
            if let pending = pendingDepartures.removeValue(forKey: key) {
                grouped[pending.listener.processName, default: []].append(pending)
            }
        }
        for (_, departures) in grouped {
            emitGroupedDepartures(departures)
        }
    }

    private func emitGroupedDepartures(_ departures: [PendingDeparture]) {
        if departures.count > 1 {
            let first = departures[0].listener
            let count = departures.count
            emitEvent(
                .stopped,
                title: "\(count) \(first.processName) processes stopped",
                port: 0,
                processName: "\(count)x \(first.processName)",
                listener: first
            )
        } else if let dep = departures.first {
            emitEvent(.stopped, for: dep.listener)
        }
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

    private func emitEvent(
        _ kind: PortEvent.Kind,
        title: String,
        port: UInt16,
        processName: String,
        listener: PortListener
    ) {
        guard notificationsEnabled else { return }

        let event = PortEvent(
            kind: kind,
            timestamp: Date(),
            port: port,
            processName: processName,
            techStack: listener.techStack,
            workingDirectory: listener.workingDirectory
        )
        events.insert(event, at: 0)
        if events.count > maxEvents { events = Array(events.prefix(maxEvents)) }

        latestEvent = event
        clearToastAfterDelay()

        // Persist to event log
        let persistentKind: PortEventRecord.Kind = kind == .started ? .started : .stopped
        eventLog.append(PortEventRecord(
            kind: persistentKind,
            port: port,
            processName: processName,
            processPath: listener.processPath,
            workingDirectory: listener.workingDirectory,
            techStack: listener.techStack,
            commandArgs: listener.commandArgs
        ))

        sendSystemNotification(title: title, body: listener.workingDirectory)
    }

    private func emitEvent(_ kind: PortEvent.Kind, for listener: PortListener) {
        let title: String = switch kind {
        case .started:
            "\(listener.processName) started on port \(listener.port)"
        case .stopped:
            "\(listener.processName) stopped (was port \(listener.port))"
        }
        emitEvent(
            kind,
            title: title,
            port: listener.port,
            processName: listener.processName,
            listener: listener
        )
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

    func rebuildItems() {
        let liveKeys = Set(listeners.map { PortHistoryEntry.historyKey(for: $0) })
        var result = listeners.map { PortItem(listener: $0) }

        if showHistory {
            let portMap = Dictionary(grouping: listeners, by: \.port)
            for (key, entry) in history.entries {
                guard !liveKeys.contains(key) else { continue }
                let conflict = portMap[entry.lastPort]?.first
                result.append(PortItem(historyEntry: entry, conflict: conflict))

                // Emit port conflict event (deduplicated)
                if let conflict,
                   eventLog.shouldEmitConflict(
                       port: entry.lastPort,
                       originalProcess: entry.processName,
                       conflictProcess: conflict.processName
                   ) {
                    eventLog.append(PortEventRecord(
                        kind: .portConflict, port: entry.lastPort,
                        processName: entry.processName,
                        processPath: entry.processPath,
                        workingDirectory: entry.workingDirectory,
                        techStack: entry.techStack,
                        commandArgs: entry.commandArgs,
                        conflictProcessName: conflict.processName
                    ))
                }
            }
        }

        result.sort { lhs, rhs in
            if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
            return lhs.port < rhs.port
        }

        items = result
    }

    func clearEvents() {
        events.removeAll()
    }
}
