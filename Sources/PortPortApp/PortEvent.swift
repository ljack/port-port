import Foundation
import PortPortCore

/// A port lifecycle event (new listener appeared or disappeared)
struct PortEvent: Identifiable {
    enum Kind {
        case started
        case stopped
    }

    let id = UUID()
    let kind: Kind
    let timestamp: Date
    let port: UInt16
    let processName: String
    let techStack: TechStack
    let workingDirectory: String

    var title: String {
        switch kind {
        case .started: "\(processName) started on port \(port)"
        case .stopped: "\(processName) stopped (was port \(port))"
        }
    }

    var icon: String {
        switch kind {
        case .started: "arrow.up.circle.fill"
        case .stopped: "arrow.down.circle.fill"
        }
    }
}
