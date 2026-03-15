import Foundation

/// A persistent port lifecycle event
public struct PortEventRecord: Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case started
        case stopped
        case portConflict
    }

    public let id: UUID
    public let kind: Kind
    public let timestamp: Date
    public let port: UInt16
    public let processName: String
    public let processPath: String
    public let workingDirectory: String
    public let techStack: TechStack
    public let commandArgs: [String]
    /// For portConflict: the process that took the port
    public let conflictProcessName: String?

    public init(
        kind: Kind, port: UInt16, processName: String, processPath: String,
        workingDirectory: String, techStack: TechStack, commandArgs: [String],
        conflictProcessName: String? = nil
    ) {
        self.id = UUID()
        self.kind = kind
        self.timestamp = Date()
        self.port = port
        self.processName = processName
        self.processPath = processPath
        self.workingDirectory = workingDirectory
        self.techStack = techStack
        self.commandArgs = commandArgs
        self.conflictProcessName = conflictProcessName
    }

    public var title: String {
        switch kind {
        case .started:
            "\(processName) started on port \(port)"
        case .stopped:
            "\(processName) stopped (was port \(port))"
        case .portConflict:
            "Port \(port) conflict: \(conflictProcessName ?? "unknown") took \(processName)'s port"
        }
    }

}
