import Darwin
import Foundation

/// Scans for all listening TCP and bound UDP ports using libproc APIs
public final class PortScanner: Sendable {

    public init() {}

    /// Perform a full scan of all listening ports
    public func scan() -> [PortListener] {
        let pids = allPIDs()
        var listeners: [PortListener] = []

        for pid in pids {
            let pidListeners = scanPID(pid)
            listeners.append(contentsOf: pidListeners)
        }

        // Deduplicate (same port+protocol+pid on both IPv4 and IPv6)
        var seen = Set<String>()
        listeners = listeners.filter { seen.insert($0.id).inserted }

        // Sort by port number
        listeners.sort { $0.port < $1.port }
        return listeners
    }

    /// Get all PIDs on the system
    private func allPIDs() -> [Int32] {
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [] }

        let pidCount = Int(count) / MemoryLayout<Int32>.size
        var pids = [Int32](repeating: 0, count: pidCount)
        let actualSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, count)
        guard actualSize > 0 else { return [] }

        let actualCount = Int(actualSize) / MemoryLayout<Int32>.size
        return Array(pids.prefix(actualCount)).filter { $0 > 0 }
    }

    /// Scan a single PID for listening sockets
    private func scanPID(_ pid: Int32) -> [PortListener] {
        let fdBufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard fdBufferSize > 0 else { return [] }

        let fdCount = Int(fdBufferSize) / MemoryLayout<proc_fdinfo>.size
        var fdInfos = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
        let actualSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fdInfos, fdBufferSize)
        guard actualSize > 0 else { return [] }

        let actualCount = Int(actualSize) / MemoryLayout<proc_fdinfo>.size
        var listeners: [PortListener] = []

        // Cache process info (only fetch once per PID if we find a listener)
        var cachedPath: String?
        var cachedName: String?
        var cachedUID: UInt32?
        var cachedStartTime: Date?
        var cachedCwd: String?
        var cachedArgs: [String]?
        var cachedTech: TechStack?

        for i in 0..<actualCount {
            let fd = fdInfos[i]
            // Only interested in socket file descriptors
            guard fd.proc_fdtype == PROX_FDTYPE_SOCKET else { continue }

            var socketInfo = socket_fdinfo()
            let infoSize = proc_pidfdinfo(
                pid,
                fd.proc_fd,
                PROC_PIDFDSOCKETINFO,
                &socketInfo,
                Int32(MemoryLayout<socket_fdinfo>.size)
            )
            guard infoSize == Int32(MemoryLayout<socket_fdinfo>.size) else { continue }

            let family = socketInfo.psi.soi_family
            guard family == AF_INET || family == AF_INET6 else { continue }

            let socketKind = socketInfo.psi.soi_kind
            let socketType = socketInfo.psi.soi_type

            var port: UInt16 = 0
            var transportProtocol: TransportProtocol?

            if socketKind == SOCKINFO_TCP && socketType == SOCK_STREAM {
                // TCP socket — check if it's in LISTEN state
                let tcpInfo = socketInfo.psi.soi_proto.pri_tcp
                let state = tcpInfo.tcpsi_state
                guard state == TSI_S_LISTEN else { continue }

                // Get local port (insi_lport is Int32, port in network byte order)
                port = portFromRaw(tcpInfo.tcpsi_ini.insi_lport)
                transportProtocol = .tcp
            } else if socketKind == SOCKINFO_IN && socketType == SOCK_DGRAM {
                // UDP socket — check if it's bound (has a local port)
                let inInfo = socketInfo.psi.soi_proto.pri_in
                port = portFromRaw(inInfo.insi_lport)
                guard port > 0 else { continue }
                transportProtocol = .udp
            } else {
                continue
            }

            guard let proto = transportProtocol, port > 0 else { continue }

            // Lazily fetch process info
            if cachedPath == nil {
                let path = ProcessInfoHelper.executablePath(for: pid)
                cachedPath = path
                let (name, uid, startTime) = ProcessInfoHelper.processInfo(for: pid)
                cachedName = name
                cachedUID = uid
                cachedStartTime = startTime
                cachedCwd = ProcessInfoHelper.workingDirectory(for: pid)
                cachedArgs = ProcessInfoHelper.commandArgs(for: pid)
                cachedTech = TechStackDetector.detect(path: path, args: cachedArgs ?? [])
            }

            let listener = PortListener(
                port: port,
                protocol: proto,
                pid: pid,
                uid: cachedUID ?? UInt32.max,
                processName: cachedName ?? "",
                processPath: cachedPath ?? "",
                workingDirectory: cachedCwd ?? "",
                techStack: cachedTech ?? .unknown,
                commandArgs: cachedArgs ?? [],
                startTime: cachedStartTime
            )
            listeners.append(listener)
        }

        return listeners
    }
}

// MARK: - Port extraction helper

/// Extract a host-order UInt16 port from the raw Int32 lport field.
/// The kernel stores the port in network byte order in the low 16 bits.
private func portFromRaw(_ raw: Int32) -> UInt16 {
    UInt16(bigEndian: UInt16(truncatingIfNeeded: raw))
}
