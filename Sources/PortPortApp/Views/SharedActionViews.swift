import SwiftUI

struct KillConfirmationView: View {
    let processName: String
    let pid: Int32
    let monitor: PortMonitor
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Kill \(processName)?")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("SIGTERM") {
                monitor.killProcess(pid: pid)
                onDismiss()
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .font(.caption2)
            .controlSize(.small)

            Button("SIGKILL") {
                monitor.killProcess(pid: pid, force: true)
                onDismiss()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .font(.caption2)
            .controlSize(.small)

            Button("Cancel") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.05))
        .transition(.opacity)
    }
}

struct PortConflictPickerView: View {
    let port: UInt16
    let conflictProcessName: String
    let suggestedPort: UInt16
    let onRestart: (UInt16) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Port \(port) in use by \(conflictProcessName)")
                .font(.caption2)
                .foregroundStyle(.orange)
            Spacer()
            Button("Use \(suggestedPort)") {
                onRestart(suggestedPort)
            }
            .buttonStyle(.bordered)
            .font(.caption2)
            .controlSize(.small)

            Button("Cancel") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.05))
        .transition(.opacity)
    }
}
