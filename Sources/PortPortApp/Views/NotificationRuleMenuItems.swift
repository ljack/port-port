import PortPortCore
import SwiftUI

struct NotificationRuleMenuItems: View {
    @Bindable var monitor: PortMonitor
    let application: NotificationApplication

    private var rule: ApplicationNotificationRule {
        monitor.notificationPreferences.rule(for: application)
    }

    var body: some View {
        Text(application.name)
        if !application.workingDirectory.isEmpty {
            Text(application.workingDirectory)
        }
        Divider()

        protocolButton(.tcp)
        protocolButton(.udp)

        Button(
            rule.includesTransientUDP ? "Ignore Transient UDP Events" : "Include Transient UDP Events",
            systemImage: rule.includesTransientUDP ? "checkmark.circle.fill" : "circle"
        ) {
            monitor.notificationPreferences.toggleTransientUDP(for: application)
        }
        Divider()

        kindButton(.started, title: "Started Events")
        kindButton(.stopped, title: "Stopped Events")
        kindButton(.portConflict, title: "Port Conflict Events")
        Divider()

        Button(
            rule.isMuted ? "Unmute Application" : "Mute Application",
            systemImage: rule.isMuted ? "bell" : "bell.slash"
        ) {
            monitor.notificationPreferences.toggleMuted(for: application)
        }

        if rule != ApplicationNotificationRule(application: application) {
            Button("Reset Notification Rules", systemImage: "arrow.counterclockwise") {
                monitor.notificationPreferences.reset(application)
            }
        }
    }

    private func protocolButton(_ transportProtocol: TransportProtocol) -> some View {
        let isEnabled = !rule.disabledProtocols.contains(transportProtocol)
        return Button(
            "\(transportProtocol.rawValue) Events",
            systemImage: isEnabled ? "checkmark.circle.fill" : "circle"
        ) {
            monitor.notificationPreferences.toggleProtocol(transportProtocol, for: application)
        }
    }

    private func kindButton(_ kind: PortEventRecord.Kind, title: String) -> some View {
        let isEnabled = !rule.disabledKinds.contains(kind)
        return Button(title, systemImage: isEnabled ? "checkmark.circle.fill" : "circle") {
            monitor.notificationPreferences.toggleKind(kind, for: application)
        }
    }
}
