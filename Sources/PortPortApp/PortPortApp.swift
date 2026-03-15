import AppKit
import SwiftUI
import UserNotifications

@main
struct PortPortApp: App {
    private static let menuBarIcon: NSImage = {
        // Try main bundle first (.app), then SPM resource bundle (debug)
        let url = Bundle.main.url(forResource: "menubar-icon", withExtension: "png")
            ?? Bundle.module.url(forResource: "menubar-icon", withExtension: "png", subdirectory: "Resources")
        if let url, let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            return img
        }
        return NSImage(systemSymbolName: "network", accessibilityDescription: "port-port")!
    }()

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var eventLog = PortEventLog()
    @State private var monitor: PortMonitor?

    var body: some Scene {
        MenuBarExtra {
            if let monitor {
                PortListView(monitor: monitor, eventLog: eventLog)
                    .frame(width: 420, height: 500)
            }
        } label: {
            Label {
                Text("port-port")
            } icon: {
                Image(nsImage: Self.menuBarIcon)
            }
        }
        .menuBarExtraStyle(.window)

        Window("Event Log", id: "event-log") {
            if let monitor {
                EventLogView(monitor: monitor, eventLog: eventLog)
                    .frame(minWidth: 500, minHeight: 400)
            }
        }
        .defaultSize(width: 600, height: 700)
    }

    init() {
        let log = PortEventLog()
        _eventLog = State(initialValue: log)
        _monitor = State(initialValue: PortMonitor(eventLog: log))
    }
}

/// AppDelegate to handle UNUserNotificationCenter delegate for foreground delivery
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("Notification auth error: \(error)")
            }
        }
    }

    /// Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
