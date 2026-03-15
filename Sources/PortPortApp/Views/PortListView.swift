import SwiftUI
import PortPortCore

struct PortListView: View {
    @Bindable var monitor: PortMonitor
    let eventLog: PortEventLog

    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var filterTech: TechStack?
    @State private var showEventLog = false

    private let currentUID = getuid()

    private var filteredItems: [PortItem] {
        var result = monitor.items

        if monitor.myPortsOnly {
            result = result.filter { item in
                if case .running(let listener) = item.status {
                    return listener.uid == currentUID
                }
                return true
            }
        }

        if monitor.devOnly {
            result = result.filter(\.isDev)
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.processName.localizedStandardContains(searchText) ||
                String($0.port).localizedStandardContains(searchText) ||
                $0.techStack.rawValue.localizedStandardContains(searchText) ||
                $0.workingDirectory.localizedStandardContains(searchText)
            }
        }

        if let tech = filterTech {
            result = result.filter { $0.techStack == tech }
        }

        return result
    }

    private var activeTechStacks: [TechStack] {
        let stacks = Set(monitor.items.map(\.techStack))
        return TechStack.allCases.filter { stacks.contains($0) }
    }

    private var runningCount: Int {
        filteredItems.filter(\.isRunning).count
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            // Toast for latest event
            if let event = monitor.latestEvent {
                toastView(event)
                Divider()
            }

            filterBar
            Divider()

            if showEventLog {
                eventLogView
                Divider()
            }

            listContent
            Divider()
            footerView
        }
        .background(.ultraThinMaterial)
    }

    private var headerView: some View {
        HStack {
            Image(systemName: "network")
                .foregroundStyle(.secondary)
            Text("port-port")
                .font(.headline)
            Spacer()
            Text(verbatim: "\(runningCount) active")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Event Log", systemImage: "list.bullet.rectangle") {
                openWindow(id: "event-log")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)

            if !monitor.events.isEmpty {
                Button("Recent Events", systemImage: "bell.badge") {
                    showEventLog.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(showEventLog ? .primary : .secondary)
            }

            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await monitor.performScan() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toastView(_ event: PortEvent) -> some View {
        HStack(spacing: 6) {
            Image(systemName: event.icon)
                .foregroundStyle(event.kind == .started ? .green : .orange)
                .font(.caption)
            Text(event.title)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Button {
                monitor.latestEvent = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(event.kind == .started
            ? Color.green.opacity(0.1)
            : Color.orange.opacity(0.1))
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: monitor.latestEvent?.id)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.caption)
            TextField("Filter...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)

            Button {
                monitor.myPortsOnly.toggle()
            } label: {
                Text("Mine")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(monitor.myPortsOnly ? 0.2 : 0.05), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(monitor.myPortsOnly ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(monitor.myPortsOnly ? "Showing my ports only" : "Showing all ports")

            Button {
                monitor.devOnly.toggle()
            } label: {
                Text("Dev")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(monitor.devOnly ? 0.2 : 0.05), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(monitor.devOnly ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(monitor.devOnly ? "Showing dev servers only" : "Showing all processes")

            Button {
                monitor.showHistory.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(monitor.showHistory ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(monitor.showHistory ? "History shown" : "History hidden")

            if !activeTechStacks.isEmpty {
                Menu {
                    Button("All") { filterTech = nil }
                    Divider()
                    ForEach(activeTechStacks, id: \.self) { tech in
                        Button(tech.rawValue) { filterTech = tech }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(filterTech?.rawValue ?? "All")
                            .font(.caption2)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var eventLogView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Event Log")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !monitor.events.isEmpty {
                    Button("Clear") {
                        monitor.clearEvents()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            if monitor.events.isEmpty {
                Text("No events yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(monitor.events.prefix(20)) { event in
                            HStack(spacing: 6) {
                                Image(systemName: event.icon)
                                    .foregroundStyle(event.kind == .started ? .green : .orange)
                                    .font(.system(size: 9))
                                Text(event.title)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Spacer()
                                Text(event.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.quaternary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder
    private var listContent: some View {
        if filteredItems.isEmpty {
            ContentUnavailableView {
                Label("No Listeners", systemImage: "network.slash")
            } description: {
                if searchText.isEmpty && filterTech == nil {
                    Text("No TCP/UDP listeners detected")
                } else {
                    Text("No matches for current filter")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(filteredItems) { item in
                        PortRowView(item: item, monitor: monitor)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var footerView: some View {
        HStack {
            if !monitor.history.entries.isEmpty {
                Button("Clear History") {
                    monitor.history.clearAll()
                    Task { await monitor.performScan() }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()

            // Grace period control
            Menu {
                ForEach([5, 10, 15, 30, 60], id: \.self) { seconds in
                    Button("\(seconds)s") {
                        monitor.gracePeriod = TimeInterval(seconds)
                    }
                }
            } label: {
                Text(verbatim: "Grace: \(Int(monitor.gracePeriod))s")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("How long to wait before notifying that a process stopped")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
