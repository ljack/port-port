import SwiftUI
import UserNotifications

@main
struct PortPortApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
