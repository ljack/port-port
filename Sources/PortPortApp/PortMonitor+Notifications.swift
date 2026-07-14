import PortPortCore

extension PortMonitor {
    func matchesNotificationFilters(_ listener: PortListener) -> Bool {
        if myPortsOnly && listener.uid != currentUID {
            return false
        }
        if devOnly && !DevServerDetector.isDev(listener) {
            return false
        }
        return true
    }

    func shouldEmitEvent(_ kind: PortEvent.Kind, for listener: PortListener) -> Bool {
        notificationPreferences.allows(
            application: notificationApplication(for: listener),
            protocol: listener.protocol,
            port: listener.port,
            kind: persistentKind(for: kind)
        )
    }

    func notificationApplication(for listener: PortListener) -> NotificationApplication {
        NotificationApplication(
            processName: listener.processName,
            processPath: listener.processPath,
            workingDirectory: listener.workingDirectory
        )
    }

    func notificationApplication(for item: PortItem) -> NotificationApplication {
        NotificationApplication(
            processName: item.processName,
            processPath: item.processPath,
            workingDirectory: item.workingDirectory
        )
    }

    var knownNotificationApplications: [NotificationApplication] {
        var applications = Dictionary(
            uniqueKeysWithValues: notificationPreferences.savedApplications.map { ($0.id, $0) }
        )
        for item in items {
            let application = notificationApplication(for: item)
            applications[application.id] = application
        }
        for event in eventLog.events {
            let application = NotificationApplication(
                processName: event.processName,
                processPath: event.processPath,
                workingDirectory: event.workingDirectory
            )
            applications[application.id] = application
        }
        return applications.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func persistentKind(for kind: PortEvent.Kind) -> PortEventRecord.Kind {
        kind == .started ? .started : .stopped
    }
}
