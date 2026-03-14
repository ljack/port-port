import Testing
@testable import PortPortCore

@Suite("TechStackDetector Tests")
struct TechStackDetectorTests {

    @Test func detectsNodeJS() {
        #expect(TechStackDetector.detect(path: "/usr/local/bin/node") == .nodeJS)
        #expect(TechStackDetector.detect(path: "/opt/homebrew/bin/node") == .nodeJS)
    }

    @Test func detectsPython() {
        #expect(TechStackDetector.detect(path: "/usr/bin/python3") == .python)
        #expect(TechStackDetector.detect(path: "/usr/local/bin/uvicorn") == .python)
        #expect(TechStackDetector.detect(path: "/usr/local/bin/gunicorn") == .python)
    }

    @Test func detectsJava() {
        #expect(TechStackDetector.detect(path: "/usr/bin/java") == .java)
    }

    @Test func detectsRuby() {
        #expect(TechStackDetector.detect(path: "/usr/bin/ruby") == .ruby)
    }

    @Test func detectsGo() {
        #expect(TechStackDetector.detect(path: "/usr/local/go/bin/myserver") == .go)
    }

    @Test func detectsRust() {
        #expect(TechStackDetector.detect(path: "/home/user/project/target/debug/myserver") == .rust)
        #expect(TechStackDetector.detect(path: "/home/user/project/target/release/myserver") == .rust)
    }

    @Test func detectsDeno() {
        #expect(TechStackDetector.detect(path: "/usr/local/bin/deno") == .deno)
    }

    @Test func detectsBun() {
        #expect(TechStackDetector.detect(path: "/usr/local/bin/bun") == .bun)
    }

    @Test func detectsElixir() {
        #expect(TechStackDetector.detect(path: "/usr/lib/erlang/erts/bin/beam.smp") == .elixir)
    }

    @Test func detectsFromArgs() {
        #expect(TechStackDetector.detect(path: "/usr/local/bin/node", args: ["server.js"]) == .nodeJS)
        #expect(TechStackDetector.detect(path: "/usr/bin/python3", args: ["app.py"]) == .python)
    }

    @Test func returnsUnknownForUnrecognized() {
        #expect(TechStackDetector.detect(path: "/usr/bin/someprocess") == .unknown)
    }
}
