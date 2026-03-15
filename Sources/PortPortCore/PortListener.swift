import Foundation

/// Represents a network port listener (TCP or UDP)
public struct PortListener: Sendable, Identifiable, Hashable, Codable {
    public var id: String { "\(`protocol`):\(port):\(pid)" }

    public let port: UInt16
    public let `protocol`: TransportProtocol
    public let pid: Int32
    public let uid: UInt32
    public let processName: String
    public let processPath: String
    public let workingDirectory: String
    public let techStack: TechStack
    public let commandArgs: [String]
    public let startTime: Date?

    /// Human-readable command string
    public var command: String {
        Self.formatCommand(args: commandArgs, processName: processName)
    }

    /// Format command args into a human-readable string
    public static func formatCommand(args: [String], processName: String) -> String {
        guard !args.isEmpty else { return processName }
        let binary = (args[0] as NSString).lastPathComponent
        if args.count == 1 { return binary }
        return ([binary] + args.dropFirst()).joined(separator: " ")
    }

    public init(
        port: UInt16,
        protocol: TransportProtocol,
        pid: Int32,
        uid: UInt32,
        processName: String,
        processPath: String,
        workingDirectory: String,
        techStack: TechStack,
        commandArgs: [String],
        startTime: Date? = nil
    ) {
        self.port = port
        self.protocol = `protocol`
        self.pid = pid
        self.uid = uid
        self.processName = processName
        self.processPath = processPath
        self.workingDirectory = workingDirectory
        self.techStack = techStack
        self.commandArgs = commandArgs
        self.startTime = startTime
    }
}

public enum TransportProtocol: String, Sendable, Codable, Hashable {
    case tcp = "TCP"
    case udp = "UDP"
}

public enum TechStack: String, Sendable, Codable, Hashable, CaseIterable {
    case nodeJS = "Node.js"
    case python = "Python"
    case java = "Java"
    case ruby = "Ruby"
    case go = "Go" // swiftlint:disable:this identifier_name
    case rust = "Rust"
    case deno = "Deno"
    case bun = "Bun"
    case elixir = "Elixir"
    case dotnet = ".NET"
    case php = "PHP"
    case unknown = "Unknown"
}
