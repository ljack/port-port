import SwiftUI
import PortPortCore

struct PortRowView: View {
    let item: PortItem
    let monitor: PortMonitor

    @State private var isHovering = false
    @State private var showConfirmKill = false
    @State private var showPortPicker = false

    var body: some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(item.isRunning ? .green : .gray)
                .frame(width: 6, height: 6)

            techBadge

            // Port number
            Text(verbatim: "\(item.port)")
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .foregroundStyle(item.isRunning ? .primary : .secondary)

            // Protocol
            Text(item.protocol.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 1) {
                Text(item.processName)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(item.isRunning ? .primary : .secondary)

                if !item.workingDirectory.isEmpty && item.workingDirectory != "/" {
                    Text(abbreviatedPath(item.workingDirectory))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                // Port conflict warning for stopped items
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

            if item.isRunning, let pid = item.pid {
                Text(verbatim: "PID \(pid)")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
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
        .alert("Kill Process?", isPresented: $showConfirmKill) {
            if let pid = item.pid {
                Button("SIGTERM", role: .destructive) {
                    monitor.killProcess(pid: pid)
                }
                Button("SIGKILL", role: .destructive) {
                    monitor.killProcess(pid: pid, force: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Kill \(item.processName) (PID \(item.pid ?? 0)) on port \(item.port)?")
        }
        .alert("Restart on different port?", isPresented: $showPortPicker) {
            let suggested = monitor.findAvailablePort(near: item.port)
            Button("Port \(suggested)") {
                monitor.restartApp(item, onPort: suggested)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Port \(item.port) is in use by \(item.portConflict?.processName ?? "another process"). Restart on a different port?")
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 4) {
            if item.isRunning {
                Button {
                    monitor.openInBrowser(port: item.port)
                } label: {
                    Image(systemName: "globe")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Open in browser")

                if !item.workingDirectory.isEmpty {
                    Button {
                        monitor.openTerminal(at: item.workingDirectory)
                    } label: {
                        Image(systemName: "terminal")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Open terminal here")
                }

                Button {
                    showConfirmKill = true
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Kill process")
            } else {
                // Stopped: show restart and remove
                if !item.commandArgs.isEmpty {
                    Button {
                        if item.portConflict != nil {
                            showPortPicker = true
                        } else {
                            monitor.restartApp(item)
                        }
                    } label: {
                        Image(systemName: "play.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .help(item.portConflict != nil
                        ? "Restart (port \(item.port) in use)"
                        : "Restart on port \(item.port)")
                }

                if !item.workingDirectory.isEmpty {
                    Button {
                        monitor.openTerminal(at: item.workingDirectory)
                    } label: {
                        Image(systemName: "terminal")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Open terminal here")
                }

                Button {
                    monitor.removeHistoryEntry(item)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from history")
            }
        }
    }

    private var techBadge: some View {
        Text(techLabel)
            .font(.system(size: 14))
            .frame(width: 22, height: 22)
            .background(techColor.opacity(item.isRunning ? 0.15 : 0.08), in: RoundedRectangle(cornerRadius: 5))
            .help(item.techStack.rawValue)
    }

    private var techLabel: String {
        switch item.techStack {
        case .nodeJS: "JS"
        case .python: "Py"
        case .java: "Jv"
        case .ruby: "Rb"
        case .go: "Go"
        case .rust: "Rs"
        case .deno: "De"
        case .bun: "Bn"
        case .elixir: "Ex"
        case .dotnet: ".N"
        case .php: "PH"
        case .unknown: "?"
        }
    }

    private var techColor: Color {
        switch item.techStack {
        case .nodeJS: .green
        case .python: .blue
        case .java: .orange
        case .ruby: .red
        case .go: .cyan
        case .rust: .brown
        case .deno: .mint
        case .bun: .pink
        case .elixir: .purple
        case .dotnet: .indigo
        case .php: .teal
        case .unknown: .gray
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
