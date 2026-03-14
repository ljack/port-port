import Foundation
import PortPortCore

/// Tool implementations that use PortPortCore
enum MCPTools: Sendable {

    /// List all listening ports
    static func listPorts() -> String {
        let scanner = PortScanner()
        let listeners = scanner.scan()

        let entries: [[String: Any]] = listeners.map { listener in
            [
                "port": Int(listener.port),
                "protocol": listener.protocol.rawValue,
                "pid": Int(listener.pid),
                "processName": listener.processName,
                "processPath": listener.processPath,
                "workingDirectory": listener.workingDirectory,
                "techStack": listener.techStack.rawValue,
                "commandArgs": listener.commandArgs,
            ] as [String: Any]
        }

        return jsonString(entries) ?? "[]"
    }

    /// Kill the process listening on a given port (SIGTERM)
    static func killPort(_ port: UInt16) -> String {
        let scanner = PortScanner()
        let listeners = scanner.scan()

        let matches = listeners.filter { $0.port == port }
        guard !matches.isEmpty else {
            return jsonString(["error": "No process found listening on port \(port)"]) ?? "{}"
        }

        var results: [[String: Any]] = []
        for listener in matches {
            let pid = listener.pid
            let ret = kill(pid, SIGTERM)
            if ret == 0 {
                results.append([
                    "status": "killed",
                    "pid": Int(pid),
                    "port": Int(listener.port),
                    "processName": listener.processName,
                ] as [String: Any])
            } else {
                let errMsg = String(cString: strerror(errno))
                results.append([
                    "status": "failed",
                    "pid": Int(pid),
                    "port": Int(listener.port),
                    "processName": listener.processName,
                    "error": errMsg,
                ] as [String: Any])
            }
        }

        return jsonString(results) ?? "[]"
    }

    /// Get detailed info for a specific port
    static func portInfo(_ port: UInt16) -> String {
        let scanner = PortScanner()
        let listeners = scanner.scan()

        let matches = listeners.filter { $0.port == port }
        guard !matches.isEmpty else {
            return jsonString(["error": "No process found listening on port \(port)"]) ?? "{}"
        }

        let entries: [[String: Any]] = matches.map { listener in
            [
                "port": Int(listener.port),
                "protocol": listener.protocol.rawValue,
                "pid": Int(listener.pid),
                "processName": listener.processName,
                "processPath": listener.processPath,
                "workingDirectory": listener.workingDirectory,
                "techStack": listener.techStack.rawValue,
                "commandArgs": listener.commandArgs,
            ] as [String: Any]
        }

        return jsonString(entries) ?? "[]"
    }

    // MARK: - Helpers

    private static func jsonString(_ value: Any) -> String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: value, options: [.sortedKeys]
        ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
