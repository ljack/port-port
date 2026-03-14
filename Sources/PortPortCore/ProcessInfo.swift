import Darwin
import Foundation

/// Helpers for retrieving process metadata via libproc and sysctl
public enum ProcessInfoHelper: Sendable {

    /// Get the full executable path for a PID
    public static func executablePath(for pid: Int32) -> String {
        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(4 * MAXPATHLEN))
        defer { pathBuffer.deallocate() }

        let result = proc_pidpath(pid, pathBuffer, UInt32(4 * MAXPATHLEN))
        guard result > 0 else { return "" }
        return String(cString: pathBuffer)
    }

    /// Get the process name, UID, and start time for a PID
    public static func processInfo(for pid: Int32) -> (name: String, uid: UInt32, startTime: Date?) {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard size > 0 else {
            let path = executablePath(for: pid)
            return ((path as NSString).lastPathComponent, UInt32.max, nil)
        }
        let name = withUnsafePointer(to: info.pbi_name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cStr in
                String(cString: cStr)
            }
        }
        let startTime = Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
        return (name, info.pbi_uid, startTime)
    }

    /// Get the working directory for a PID using proc_pidinfo with PROC_PIDVNODEPATHINFO
    public static func workingDirectory(for pid: Int32) -> String {
        var vnodeInfo = proc_vnodepathinfo()
        let size = proc_pidinfo(
            pid,
            PROC_PIDVNODEPATHINFO,
            0,
            &vnodeInfo,
            Int32(MemoryLayout<proc_vnodepathinfo>.size)
        )
        guard size > 0 else { return "" }

        return withUnsafePointer(to: vnodeInfo.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStr in
                String(cString: cStr)
            }
        }
    }

    /// Get the command-line arguments for a PID via sysctl KERN_PROCARGS2
    public static func commandArgs(for pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0

        // First call to get buffer size
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else {
            return []
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }

        guard sysctl(&mib, 3, buffer, &size, nil, 0) == 0 else {
            return []
        }

        // First 4 bytes are argc
        let argc = buffer.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
        guard argc > 0 else { return [] }

        // Skip argc (4 bytes), then skip the executable path (null-terminated)
        var offset = MemoryLayout<Int32>.size

        // Skip exec path
        while offset < size && buffer[offset] != 0 { offset += 1 }
        // Skip null terminators
        while offset < size && buffer[offset] == 0 { offset += 1 }

        // Now read argc strings
        var args: [String] = []
        for _ in 0..<argc {
            guard offset < size else { break }
            let start = buffer.advanced(by: offset)
            let str = String(cString: start)
            args.append(str)
            offset += str.utf8.count + 1
        }

        return args
    }
}
