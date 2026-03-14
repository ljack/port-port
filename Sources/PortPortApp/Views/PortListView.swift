import AppKit
import SwiftUI
import PortPortCore

struct PortListView: View {
    let monitor: PortMonitor

    @State private var searchText = ""
    @State private var filterTech: TechStack?
    @State private var myPortsOnly = true

    private let currentUID = getuid()

    private var filteredItems: [PortItem] {
        var result = monitor.items

        if myPortsOnly {
            result = result.filter { item in
                if case .running(let listener) = item.status {
                    return listener.uid == currentUID
                }
                return true // always show history items (they were ours)
            }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.processName.lowercased().contains(query) ||
                String($0.port).contains(query) ||
                $0.techStack.rawValue.lowercased().contains(query) ||
                $0.workingDirectory.lowercased().contains(query)
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
            filterBar
            Divider()
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
            Button {
                Task { await monitor.performScan() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                myPortsOnly.toggle()
            } label: {
                Text("Mine")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        myPortsOnly ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.quaternary),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .foregroundStyle(myPortsOnly ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(myPortsOnly ? "Showing my ports only" : "Showing all ports")

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
                LazyVStack(spacing: 1) {
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
