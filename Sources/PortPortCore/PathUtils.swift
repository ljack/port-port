import Foundation

/// Path abbreviation utilities
public enum PathUtils {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path()

    public static func abbreviate(_ path: String) -> String {
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
