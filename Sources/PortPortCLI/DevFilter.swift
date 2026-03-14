import Foundation
import PortPortCore

/// Dev server detection — thin wrapper around shared DevServerDetector
enum DevFilter {
    static func isDev(_ listener: PortListener) -> Bool {
        DevServerDetector.isDev(listener)
    }

    static func filter(_ listeners: [PortListener], mine: Bool, dev: Bool, tech: TechStack? = nil) -> [PortListener] {
        var result = listeners
        if mine {
            let uid = getuid()
            result = result.filter { $0.uid == uid }
        }
        if dev {
            result = result.filter { DevServerDetector.isDev($0) }
        }
        if let tech {
            result = result.filter { $0.techStack == tech }
        }
        return result
    }
}
