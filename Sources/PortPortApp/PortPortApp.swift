import SwiftUI

@main
struct PortPortApp: App {
    @State private var monitor = PortMonitor()

    var body: some Scene {
        MenuBarExtra {
            PortListView(monitor: monitor)
                .frame(width: 420, height: 500)
        } label: {
            Label {
                Text("port-port")
            } icon: {
                Image(systemName: "network")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
