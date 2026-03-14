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
        guard !commandArgs.isEmpty else { return processName }
        // Show just the binary name + args, not the full path
        let binary = (commandArgs[0] as NSString).lastPathComponent
        if commandArgs.count == 1 { return binary }
        return ([binary] + commandArgs.dropFirst()).joined(separator: " ")
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
    case go = "Go"
    case rust = "Rust"
    case deno = "Deno"
    case bun = "Bun"
    case elixir = "Elixir"
    case dotnet = ".NET"
    case php = "PHP"
    case unknown = "Unknown"
}
