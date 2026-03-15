import Foundation
import Testing
@testable import PortPortCore

@Suite("DevServerDetector Tests")
struct DevServerDetectorTests {

    private let home = FileManager.default.homeDirectoryForCurrentUser.path()

    private func makeListener(
        port: UInt16 = 8080,
        processName: String = "test",
        processPath: String = "/usr/bin/test",
        workingDirectory: String? = nil,
        techStack: TechStack = .unknown,
        commandArgs: [String] = []
    ) -> PortListener {
        let dir = workingDirectory ?? "\(home)/_dev/myproject"
        return PortListener(
            port: port, protocol: .tcp, pid: 1, uid: 501,
            processName: processName, processPath: processPath,
            workingDirectory: dir, techStack: techStack,
            commandArgs: commandArgs
        )
    }

    @Test func pythonInProjectDir() {
        let listener = makeListener(processPath: "/usr/bin/python3", techStack: .python,
                                    commandArgs: ["/usr/bin/python3", "-m", "http.server", "8080"])
        #expect(DevServerDetector.isDev(listener))
    }

    @Test func nodeInProjectDir() {
        let listener = makeListener(processPath: "/usr/local/bin/node", techStack: .nodeJS,
                                    commandArgs: ["/usr/local/bin/node", "server.js"])
        #expect(DevServerDetector.isDev(listener))
    }

    @Test func systemProcessNotDev() {
        let listener = makeListener(
            processName: "ControlCenter",
            processPath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
            workingDirectory: "/")
        #expect(!DevServerDetector.isDev(listener))
    }

    @Test func appInLibraryNotDev() {
        let listener = makeListener(
            processName: "Notion Helper",
            processPath: "/Applications/Notion.app/Contents/MacOS/Notion Helper",
            workingDirectory: "\(home)/Library/Containers/notion")
        #expect(!DevServerDetector.isDev(listener))
    }

    @Test func daemonInClaudeDirNotDev() {
        let listener = makeListener(processName: "bun",
                                    processPath: "\(home)/.bun/bin/bun",
                                    workingDirectory: "\(home)/.claude/plugins/cache/foo",
                                    techStack: .bun,
                                    commandArgs: ["bun", "worker-service.cjs", "--daemon"])
        #expect(!DevServerDetector.isDev(listener))
    }

    @Test func viteArgAlwaysDev() {
        let listener = makeListener(processPath: "/usr/local/bin/node",
                                    workingDirectory: "/",
                                    commandArgs: ["node", "node_modules/.bin/vite"])
        #expect(DevServerDetector.isDev(listener))
    }

    @Test func npmRunDevAlwaysDev() {
        let listener = makeListener(processPath: "/usr/local/bin/node",
                                    workingDirectory: "/tmp/project",
                                    commandArgs: ["node", "npm", "run", "dev"])
        #expect(DevServerDetector.isDev(listener))
    }

    @Test func downloadsNotDev() {
        let listener = makeListener(processName: "bun",
                                    processPath: "\(home)/.bun/bin/bun",
                                    workingDirectory: "\(home)/Downloads/something",
                                    techStack: .bun)
        #expect(!DevServerDetector.isDev(listener))
    }

    @Test func rustTargetDebugIsDev() {
        let listener = makeListener(processPath: "\(home)/_dev/myrust/target/debug/myserver",
                                    workingDirectory: "\(home)/_dev/myrust")
        #expect(DevServerDetector.isDev(listener))
    }

    @Test func googleDriveNotDev() {
        let listener = makeListener(
            processName: "Google Drive",
            processPath: "/Applications/Google Drive.app/Contents/MacOS/Google Drive",
            workingDirectory: "\(home)/Google/")
        #expect(!DevServerDetector.isDev(listener))
    }
}
