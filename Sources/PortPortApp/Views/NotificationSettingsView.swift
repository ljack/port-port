import SwiftUI

struct NotificationSettingsView: View {
    @Bindable var monitor: PortMonitor

    var body: some View {
        Form {
            Section("Event Defaults") {
                LabeledContent("Transient UDP sockets") {
                    Text("Ignored")
                        .foregroundStyle(.secondary)
                }
                Text(
                    "Short-lived UDP sockets in the dynamic port range stay visible in the live list, "
                        + "but do not create events or notifications unless enabled for an application."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Applications") {
                if monitor.knownNotificationApplications.isEmpty {
                    ContentUnavailableView(
                        "No Applications",
                        systemImage: "bell.slash",
                        description: Text("Applications appear after PortPort detects a listening port.")
                    )
                } else {
                    ForEach(monitor.knownNotificationApplications) { application in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(application.name)
                                if !application.workingDirectory.isEmpty {
                                    Text(application.workingDirectory)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            NotificationRuleMenu(monitor: monitor, application: application)
                                .menuStyle(.button)
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 460)
        .navigationTitle("Notifications")
    }
}
