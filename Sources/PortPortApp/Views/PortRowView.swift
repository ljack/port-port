import SwiftUI
import PortPortCore

struct PortRowView: View {
    let item: PortItem
    let monitor: PortMonitor

    @State private var isHovering = false
    @State private var showConfirmKill = false
    @State private var showPortPicker = false

    var body: some View {
        VStack(spacing: 0) {
            mainRow

            // Inline kill confirmation
            if showConfirmKill, let pid = item.pid {
                KillConfirmationView(
                    processName: item.processName, pid: pid,
                    monitor: monitor, onDismiss: { showConfirmKill = false }
                )
            }

            // Inline port conflict picker
            if showPortPicker {
                PortConflictPickerView(
                    port: item.port,
                    conflictProcessName: item.portConflict?.processName ?? "?",
                    suggestedPort: monitor.findAvailablePort(near: item.port),
                    onRestart: { port in
                        monitor.restartApp(item, onPort: port)
                        showPortPicker = false
                    },
                    onDismiss: { showPortPicker = false }
                )
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showConfirmKill)
        .animation(.easeInOut(duration: 0.15), value: showPortPicker)
    }

    private var mainRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(item.isRunning ? .green : .gray)
                .frame(width: 6, height: 6)

            TechBadge(techStack: item.techStack, opacity: item.isRunning ? 0.15 : 0.08)

            Text(verbatim: "\(item.port)")
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .foregroundStyle(item.isRunning ? .primary : .secondary)

            Text(item.protocol.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 1) {
                Text(item.command)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(item.isRunning ? .primary : .secondary)
                    .help(item.commandArgs.joined(separator: " "))

                if !item.workingDirectory.isEmpty && item.workingDirectory != "/" {
                    Text(PathUtils.abbreviate(item.workingDirectory))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if let conflict = item.portConflict, !item.isRunning {
                    Text("Port \(conflict.port) used by \(conflict.processName)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isHovering {
                actionButtons
            }

            if item.isRunning, let start = item.startTime {
                Text(start, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .help("Process uptime")
            } else if let lastSeen = item.lastSeen {
                Text(lastSeen, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovering ? Color.primary.opacity(0.05) : .clear)
        .opacity(item.isRunning ? 1.0 : 0.7)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 4) {
            if item.isRunning {
                Button("Open in Browser", systemImage: "globe") {
                    monitor.openInBrowser(port: item.port)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.caption)

                if !item.workingDirectory.isEmpty {
                    Button("Open Terminal", systemImage: "terminal") {
                        monitor.openTerminal(at: item.workingDirectory)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.caption)
                }

                Button("Kill Process", systemImage: "xmark.circle") {
                    showConfirmKill.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.red)
            } else {
                if !item.commandArgs.isEmpty {
                    Button("Restart", systemImage: "play.circle") {
                        if item.portConflict != nil {
                            showPortPicker.toggle()
                        } else {
                            monitor.restartApp(item)
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.green)
                }

                if !item.workingDirectory.isEmpty {
                    Button("Open Terminal", systemImage: "terminal") {
                        monitor.openTerminal(at: item.workingDirectory)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.caption)
                }

                Button("Remove from History", systemImage: "trash") {
                    monitor.removeHistoryEntry(item)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
