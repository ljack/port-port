import PortPortCore
import SwiftUI

struct NotificationRuleMenu: View {
    @Bindable var monitor: PortMonitor
    let application: NotificationApplication

    private var rule: ApplicationNotificationRule {
        monitor.notificationPreferences.rule(for: application)
    }

    var body: some View {
        Menu {
            NotificationRuleMenuItems(monitor: monitor, application: application)
        } label: {
            Label(
                "Notifications for \(application.name)",
                systemImage: rule.isMuted ? "bell.slash" : "bell"
            )
        }
    }
}
