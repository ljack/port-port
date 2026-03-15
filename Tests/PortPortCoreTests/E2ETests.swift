import Foundation
import Testing
@testable import PortPortCore

@Suite("End-to-End Tests",
       .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil,
                "E2E tests require local environment with libproc access"))
struct E2ETests {

    @Test func scanFindsPythonHTTPServer() async throws {
        // Start a python http server, verify scanner finds it, then kill it
        let port: UInt16 = 19876
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", String(port)]
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { process.terminate() }

        // Wait for server to start listening
        try await Task.sleep(for: .seconds(1))

        let scanner = PortScanner()
        let results = scanner.scan()
        let match = results.first(where: { $0.port == port })

        #expect(match != nil, "Scanner should find python http.server on port \(port)")
        if let match {
            #expect(match.protocol == .tcp)
            #expect(match.techStack == .python)
            #expect(match.pid == process.processIdentifier)
            #expect(match.processPath.contains("python") || match.processPath.contains("Python"))
            #expect(match.command.contains("http.server"))
            #expect(match.startTime != nil)
        }
    }

    @Test func scanDetectsServerAppearAndDisappear() async throws {
        let port: UInt16 = 19877
        let scanner = PortScanner()

        // Verify port is not in use
        let before = scanner.scan()
        #expect(!before.contains(where: { $0.port == port }))

        // Start server
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", String(port)]
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        try await Task.sleep(for: .seconds(1))

        // Verify it appears
        let during = scanner.scan()
        #expect(during.contains(where: { $0.port == port }))

        // Kill it
        process.terminate()
        process.waitUntilExit()
        try await Task.sleep(for: .seconds(1))

        // Verify it's gone
        let after = scanner.scan()
        #expect(!after.contains(where: { $0.port == port }))
    }

    @Test func processMetadataAccuracy() async throws {
        let port: UInt16 = 19878
        let tmpDir = NSTemporaryDirectory()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", String(port)]
        process.currentDirectoryURL = URL(fileURLWithPath: tmpDir)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { process.terminate() }

        try await Task.sleep(for: .seconds(1))

        let pid = process.processIdentifier

        // Test individual ProcessInfoHelper methods
        let path = ProcessInfoHelper.executablePath(for: pid)
        #expect(path.contains("python") || path.contains("Python"))

        let (name, uid, startTime) = ProcessInfoHelper.processInfo(for: pid)
        #expect(!name.isEmpty)
        #expect(uid == getuid())
        #expect(startTime != nil)
        if let start = startTime {
            #expect(abs(start.timeIntervalSinceNow) < 10, "Start time should be recent")
        }

        let cwd = ProcessInfoHelper.workingDirectory(for: pid)
        // CWD should match or be the resolved path
        #expect(!cwd.isEmpty)

        let args = ProcessInfoHelper.commandArgs(for: pid)
        #expect(args.contains(where: { $0.contains("http.server") }))
        #expect(args.contains(String(port)))
    }

    @Test func historyPersistence() throws {
        let store = PortHistoryStore()

        // Create a fake listener with a unique path so it doesn't collide
        let listener = PortListener(
            port: 29999, protocol: .tcp, pid: 1, uid: 501,
            processName: "Python", processPath: "/usr/bin/python3",
            workingDirectory: "/tmp/test-history-\(UUID().uuidString)", techStack: .python,
            commandArgs: ["/usr/bin/python3", "-m", "http.server", "29999"]
        )
        let testKey = PortHistoryEntry.historyKey(for: listener)

        // Update history
        store.update(from: [listener])

        // Load fresh and verify
        let fresh = PortHistoryStore()
        let loaded = fresh.load()
        let entry = loaded[testKey]
        #expect(entry != nil)
        if let entry {
            #expect(entry.lastPort == 29999)
            #expect(entry.processName == "Python")
            #expect(entry.techStack == .python)
            #expect(entry.commandArgs.contains("-m"))

            // Clean up
            fresh.remove(entry)
        }
    }

    @Test func mcpServerRespondsToInitialize() throws {
        // Test the MCP binary responds correctly
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ".build/arm64-apple-macosx/debug/port-port-mcp")
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        defer { process.terminate() }

        let request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"1.0\"}}}\n"
        inputPipe.fileHandleForWriting.write(request.data(using: .utf8)!)
        inputPipe.fileHandleForWriting.closeFile()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let response = String(data: data, encoding: .utf8) ?? ""

        #expect(response.contains("\"protocolVersion\""))
        #expect(response.contains("port-port"))
        #expect(response.contains("\"tools\""))
    }

    @Test func cliListOutputFormat() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ".build/arm64-apple-macosx/debug/port-port-cli")
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.arguments = ["list", "--all", "--json"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]

        #expect(json != nil, "CLI --json should produce valid JSON array")
        if let first = json?.first {
            #expect(first["port"] != nil)
            #expect(first["protocol"] != nil)
            #expect(first["processName"] != nil)
            #expect(first["techStack"] != nil)
            #expect(first["uid"] != nil)
        }
    }
}
