import Foundation

/// A user-facing application identity for lifecycle-event preferences.
public struct NotificationApplication: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let workingDirectory: String
    public let processPath: String

    public init(processName: String, processPath: String, workingDirectory: String) {
        let normalizedDirectory = Self.normalizedDirectory(workingDirectory)
        if !normalizedDirectory.isEmpty {
            self.id = "directory:\(normalizedDirectory)"
            self.name = URL(fileURLWithPath: normalizedDirectory).lastPathComponent
            self.workingDirectory = normalizedDirectory
        } else {
            self.id = "executable:\(processPath)"
            self.name = processName.isEmpty ? URL(fileURLWithPath: processPath).lastPathComponent : processName
            self.workingDirectory = ""
        }
        self.processPath = processPath
    }

    private static func normalizedDirectory(_ path: String) -> String {
        guard !path.isEmpty, path != "/" else { return "" }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
