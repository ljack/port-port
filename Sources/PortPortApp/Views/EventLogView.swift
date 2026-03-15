import SwiftUI
import PortPortCore

struct EventLogView: View {
    let monitor: PortMonitor
    let eventLog: PortEventLog

    @State private var searchText = ""
    @State private var filterKind: PortEventRecord.Kind?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var filteredEvents: [PortEventRecord] {
        var result = eventLog.events

        if let kind = filterKind {
            result = result.filter { $0.kind == kind }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.processName.lowercased().contains(query) ||
                String($0.port).contains(query) ||
                $0.workingDirectory.lowercased().contains(query) ||
                $0.techStack.rawValue.lowercased().contains(query)
            }
        }

        return result
    }

    private var groupedEvents: [(String, [PortEventRecord])] {
        let calendar = Calendar.current
        let formatter = Self.dateFormatter
        let grouped = Dictionary(grouping: filteredEvents) { event -> String in
            let date = event.timestamp
            if calendar.isDateInToday(date) { return "Today" }
            if calendar.isDateInYesterday(date) { return "Yesterday" }
            return formatter.string(from: date)
        }
        return grouped.sorted { a, b in
            guard let aFirst = a.value.first, let bFirst = b.value.first else { return false }
            return aFirst.timestamp > bFirst.timestamp
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            filterBar
            Divider()

            if filteredEvents.isEmpty {
                ContentUnavailableView {
                    Label("No Events", systemImage: "clock")
                } description: {
                    if searchText.isEmpty && filterKind == nil {
                        Text("Events will appear here as ports start and stop")
                    } else {
                        Text("No events match the current filter")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                eventList
            }
        }
        .background(.ultraThinMaterial)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var toolbar: some View {
        HStack {
            Image(systemName: "clock.arrow.2.circlepath")
                .foregroundStyle(.secondary)
            Text("Event Log")
                .font(.headline)
            Spacer()
            Text(verbatim: "\(filteredEvents.count) events")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !eventLog.events.isEmpty {
                Button("Clear All") {
                    eventLog.clearAll()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.caption)
            TextField("Filter by name, port, path...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)

            ForEach(PortEventRecord.Kind.allCases, id: \.self) { kind in
                Button {
                    filterKind = filterKind == kind ? nil : kind
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 8))
                        Text(kind.filterLabel)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        filterKind == kind
                            ? AnyShapeStyle(kind.color.opacity(0.2))
                            : AnyShapeStyle(.quaternary),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .foregroundStyle(filterKind == kind ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var eventList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(groupedEvents, id: \.0) { dayLabel, events in
                    Section {
                        ForEach(events) { event in
                            EventRowView(event: event, monitor: monitor, eventLog: eventLog)
                            Divider().padding(.leading, 44)
                        }
                    } header: {
                        HStack {
                            Text(dayLabel)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                    }
                }
            }
        }
    }
}

// MARK: - Kind UI helpers

extension PortEventRecord.Kind {
    var icon: String {
        switch self {
        case .started: "arrow.up.circle.fill"
        case .stopped: "arrow.down.circle.fill"
        case .portConflict: "exclamationmark.triangle.fill"
        }
    }

    var filterLabel: String {
        switch self {
        case .started: "Started"
        case .stopped: "Stopped"
        case .portConflict: "Conflicts"
        }
    }

    var color: Color {
        switch self {
        case .started: .green
        case .stopped: .orange
        case .portConflict: .red
        }
    }
}

// MARK: - Event Row

struct EventRowView: View {
    let event: PortEventRecord
    let monitor: PortMonitor
    let eventLog: PortEventLog

    @State private var isHovering = false
    @State private var showConfirmKill = false
    @State private var showPortPicker = false

    private var matchingListener: PortListener? {
        monitor.listeners.first { $0.port == event.port && $0.processName == event.processName }
    }

    private var isStillRunning: Bool {
        matchingListener != nil
    }

    private var portConflict: PortListener? {
        guard event.kind == .stopped || event.kind == .portConflict else { return nil }
        return monitor.listeners.first { $0.port == event.port && $0.processName != event.processName }
    }

    var body: some View {
        VStack(spacing: 0) {
            mainRow

            if showConfirmKill, let listener = matchingListener {
                KillConfirmationView(
                    processName: event.processName, pid: listener.pid,
                    monitor: monitor, onDismiss: { showConfirmKill = false }
                )
                .padding(.horizontal, 4)
            }

            if showPortPicker {
                PortConflictPickerView(
                    port: event.port,
                    conflictProcessName: portConflict?.processName ?? "?",
                    suggestedPort: monitor.findAvailablePort(near: event.port),
                    onRestart: { port in
                        restartFromEvent(onPort: port)
                        showPortPicker = false
                    },
                    onDismiss: { showPortPicker = false }
                )
                .padding(.horizontal, 4)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showConfirmKill)
        .animation(.easeInOut(duration: 0.15), value: showPortPicker)
    }

    private var mainRow: some View {
        HStack(spacing: 8) {
            Image(systemName: event.kind.icon)
                .foregroundStyle(event.kind.color)
                .font(.system(size: 14))
                .frame(width: 20)

            TechBadge(techStack: event.techStack, opacity: 0.12)

            Text(verbatim: "\(event.port)")
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .foregroundStyle(isStillRunning ? .primary : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if !event.workingDirectory.isEmpty && event.workingDirectory != "/" {
                    Text(PathUtils.abbreviate(event.workingDirectory))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if let conflict = portConflict, event.kind == .stopped {
                    Text("Port now used by \(conflict.processName)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isHovering {
                actionButtons
            }

            Text(event.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isHovering ? Color.primary.opacity(0.05) : .clear)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 4) {
            if isStillRunning {
                Button {
                    monitor.openInBrowser(port: event.port)
                } label: {
                    Image(systemName: "globe").font(.caption)
                }
                .buttonStyle(.plain)
                .help("Open in browser")

                if !event.workingDirectory.isEmpty {
                    Button {
                        monitor.openTerminal(at: event.workingDirectory)
                    } label: {
                        Image(systemName: "terminal").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Open terminal here")
                }

                Button {
                    showConfirmKill.toggle()
                } label: {
                    Image(systemName: "xmark.circle").font(.caption).foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Kill process")
            } else if event.kind == .stopped {
                if !event.commandArgs.isEmpty {
                    Button {
                        if portConflict != nil {
                            showPortPicker.toggle()
                        } else {
                            restartFromEvent()
                        }
                    } label: {
                        Image(systemName: "play.circle").font(.caption).foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .help(portConflict != nil
                        ? "Restart (port \(event.port) in use)"
                        : "Restart on port \(event.port)")
                }

                if !event.workingDirectory.isEmpty {
                    Button {
                        monitor.openTerminal(at: event.workingDirectory)
                    } label: {
                        Image(systemName: "terminal").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Open terminal here")
                }
            }

            Button {
                eventLog.remove(id: event.id)
            } label: {
                Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove event")
        }
    }

    private func restartFromEvent(onPort: UInt16? = nil) {
        let item = PortItem(fromEvent: event, conflict: portConflict)
        monitor.restartApp(item, onPort: onPort)
    }
}
