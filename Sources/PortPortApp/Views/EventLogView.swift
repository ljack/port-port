import SwiftUI
import PortPortCore

struct EventLogView: View {
    let monitor: PortMonitor
    let eventLog: PortEventLog

    @State private var searchText = ""
    @State private var filterKind: PortEventRecord.Kind?

    private var filteredEvents: [PortEventRecord] {
        var result = eventLog.events

        if let kind = filterKind {
            result = result.filter { $0.kind == kind }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.processName.localizedStandardContains(searchText) ||
                String($0.port).localizedStandardContains(searchText) ||
                $0.workingDirectory.localizedStandardContains(searchText) ||
                $0.techStack.rawValue.localizedStandardContains(searchText)
            }
        }

        return result
    }

    private var groupedEvents: [(String, [PortEventRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEvents) { event -> String in
            let date = event.timestamp
            if calendar.isDateInToday(date) { return "Today" }
            if calendar.isDateInYesterday(date) { return "Yesterday" }
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return grouped.sorted { lhs, rhs in
            guard let lhsFirst = lhs.value.first, let rhsFirst = rhs.value.first else { return false }
            return lhsFirst.timestamp > rhsFirst.timestamp
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
                        kind.color.opacity(filterKind == kind ? 0.2 : 0.05),
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
                Button("Open in Browser", systemImage: "globe") {
                    monitor.openInBrowser(port: event.port)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.caption)

                if !event.workingDirectory.isEmpty {
                    Button("Open Terminal", systemImage: "terminal") {
                        monitor.openTerminal(at: event.workingDirectory)
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
            } else if event.kind == .stopped {
                if !event.commandArgs.isEmpty {
                    Button("Restart", systemImage: "play.circle") {
                        if portConflict != nil {
                            showPortPicker.toggle()
                        } else {
                            restartFromEvent()
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.green)
                }

                if !event.workingDirectory.isEmpty {
                    Button("Open Terminal", systemImage: "terminal") {
                        monitor.openTerminal(at: event.workingDirectory)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.caption)
                }
            }

            Button("Remove Event", systemImage: "trash") {
                eventLog.remove(id: event.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func restartFromEvent(onPort: UInt16? = nil) {
        let item = PortItem(fromEvent: event, conflict: portConflict)
        monitor.restartApp(item, onPort: onPort)
    }
}
