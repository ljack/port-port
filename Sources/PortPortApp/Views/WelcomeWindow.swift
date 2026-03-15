import AppKit
import SwiftUI

enum AppConstants {
    static let hideWelcomeKey = "hideWelcomeWindow"
}

struct WelcomeView: View {
    let onDismiss: () -> Void

    @State private var pulse = false
    @State private var dontShowAgain = false

    private static let appIcon: NSImage? = {
        let url = Bundle.main.url(forResource: "menubar-icon", withExtension: "png")
            ?? Bundle.module.url(forResource: "menubar-icon", withExtension: "png", subdirectory: "Resources")
        guard let url, let img = NSImage(contentsOf: url) else { return nil }
        return img
    }()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if let icon = Self.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .opacity(0.8)
            }

            Text("PortPort")
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            Text("Monitoring your ports from the menu bar")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            // Show the actual menu bar icon so users know what to look for
            Text("Look for this icon in your menu bar")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                // Fake neighboring icons
                Image(systemName: "wifi")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)

                // The actual PortPort icon, highlighted
                if let icon = Self.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .padding(6)
                        .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                        .offset(y: pulse ? -2 : 2)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
                }

                Image(systemName: "battery.75percent")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            Toggle("Don't show on launch", isOn: $dontShowAgain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .onChange(of: dontShowAgain) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: AppConstants.hideWelcomeKey)
                }

            Button {
                onDismiss()
            } label: {
                Text("Got it")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .padding(24)
        .frame(width: 280, height: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { pulse = true }
    }
}

/// Manages the welcome window with animation to menu bar
@MainActor
final class WelcomeWindowController {
    private var window: NSWindow?
    private var windowDelegate: WindowCloseDelegate?

    func show() {
        let view = WelcomeView(onDismiss: { [weak self] in
            self?.animateToMenuBar()
        })

        let hostingView = NSHostingView(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 380),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isOpaque = true
        panel.backgroundColor = .windowBackgroundColor
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.center()

        // Shift up a bit from center
        if let frame = panel.screen?.visibleFrame {
            let originX = frame.midX - 140
            let originY = frame.midY
            panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        }

        panel.isReleasedWhenClosed = false
        let delegate = WindowCloseDelegate { [weak self] in self?.window = nil }
        panel.delegate = delegate
        self.windowDelegate = delegate
        panel.orderFrontRegardless()
        self.window = panel
    }

    private func animateToMenuBar() {
        guard let window else { return }

        // Get the menu bar area (top center of screen)
        guard let screen = window.screen else {
            window.close()
            self.window = nil
            return
        }

        let menuBarTarget = NSPoint(
            x: screen.frame.midX,
            y: screen.frame.maxY - 12
        )

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)

            // Shrink and move to menu bar
            let targetSize = NSSize(width: 40, height: 40)
            let targetOrigin = NSPoint(
                x: menuBarTarget.x - 20,
                y: menuBarTarget.y - 20
            )
            window.animator().setFrame(
                NSRect(origin: targetOrigin, size: targetSize),
                display: true
            )
            window.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.window?.close()
                self?.window = nil
                self?.windowDelegate = nil
            }
        })
    }
}

/// Handles window close to prevent leaks
private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in onClose() }
    }
}
