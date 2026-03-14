import Testing
@testable import PortPortCore

@Suite("DevServerDetector Tests")
struct DevServerDetectorTests {

    private func makeListener(
        port: UInt16 = 8080,
        processName: String = "test",
        processPath: String = "/usr/bin/test",
        workingDirectory: String = "/Users/jarkko/_dev/myproject",
        techStack: TechStack = .unknown,
        commandArgs: [String] = []
    ) -> PortListener {
        PortListener(
            port: port, protocol: .tcp, pid: 1, uid: 501,
            processName: processName, processPath: processPath,
            workingDirectory: workingDirectory, techStack: techStack,
            commandArgs: commandArgs
        )
    }

    @Test func pythonInProjectDir() {
        let l = makeListener(processPath: "/usr/bin/python3", techStack: .python,
                            commandArgs: ["/usr/bin/python3", "-m", "http.server", "8080"])
        #expect(DevServerDetector.isDev(l))
    }

    @Test func nodeInProjectDir() {
        let l = makeListener(processPath: "/usr/local/bin/node", techStack: .nodeJS,
                            commandArgs: ["/usr/local/bin/node", "server.js"])
        #expect(DevServerDetector.isDev(l))
    }

    @Test func systemProcessNotDev() {
        let l = makeListener(processName: "ControlCenter",
                            processPath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
                            workingDirectory: "/")
        #expect(!DevServerDetector.isDev(l))
    }

    @Test func appInLibraryNotDev() {
        let l = makeListener(processName: "Notion Helper",
                            processPath: "/Applications/Notion.app/Contents/MacOS/Notion Helper",
                            workingDirectory: "/Users/jarkko/Library/Containers/notion")
        #expect(!DevServerDetector.isDev(l))
    }

    @Test func daemonInClaudeDirNotDev() {
        let l = makeListener(processName: "bun",
                            processPath: "/Users/jarkko/.bun/bin/bun",
                            workingDirectory: "/Users/jarkko/.claude/plugins/cache/foo",
                            techStack: .bun,
                            commandArgs: ["bun", "worker-service.cjs", "--daemon"])
        #expect(!DevServerDetector.isDev(l))
    }

    @Test func viteArgAlwaysDev() {
        let l = makeListener(processPath: "/usr/local/bin/node",
                            workingDirectory: "/",
                            commandArgs: ["node", "node_modules/.bin/vite"])
        #expect(DevServerDetector.isDev(l))
    }

    @Test func npmRunDevAlwaysDev() {
        let l = makeListener(processPath: "/usr/local/bin/node",
                            workingDirectory: "/tmp/project",
                            commandArgs: ["node", "npm", "run", "dev"])
        #expect(DevServerDetector.isDev(l))
    }

    @Test func downloadsNotDev() {
        let l = makeListener(processName: "bun",
                            processPath: "/Users/jarkko/.bun/bin/bun",
                            workingDirectory: "/Users/jarkko/Downloads/something",
                            techStack: .bun)
        #expect(!DevServerDetector.isDev(l))
    }

    @Test func rustTargetDebugIsDev() {
        let l = makeListener(processPath: "/Users/jarkko/_dev/myrust/target/debug/myserver",
                            workingDirectory: "/Users/jarkko/_dev/myrust")
        #expect(DevServerDetector.isDev(l))
    }

    @Test func googleDriveNotDev() {
        let l = makeListener(processName: "Google Drive",
                            processPath: "/Applications/Google Drive.app/Contents/MacOS/Google Drive",
                            workingDirectory: "/Users/jarkko/Google/")
        #expect(!DevServerDetector.isDev(l))
    }
}
