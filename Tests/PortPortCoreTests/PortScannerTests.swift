import Testing
@testable import PortPortCore

@Suite("PortScanner Tests")
struct PortScannerTests {

    @Test func scanReturnsResults() {
        let scanner = PortScanner()
        let results = scanner.scan()
        // On any system there should be at least a few listening ports
        #expect(!results.isEmpty, "Expected at least one listening port on the system")
    }

    @Test func scanResultsHaveValidPorts() {
        let scanner = PortScanner()
        let results = scanner.scan()
        for listener in results {
            #expect(listener.port > 0)
            #expect(listener.pid > 0)
            #expect(!listener.processName.isEmpty || !listener.processPath.isEmpty)
        }
    }

    @Test func scanResultsSortedByPort() {
        let scanner = PortScanner()
        let results = scanner.scan()
        guard results.count >= 2 else { return }
        for index in 1..<results.count {
            #expect(results[index].port >= results[index - 1].port)
        }
    }

    @Test func scanPerformance() async {
        let scanner = PortScanner()
        let start = ContinuousClock.now
        _ = scanner.scan()
        let elapsed = ContinuousClock.now - start
        // Should complete in under 1 second
        #expect(elapsed < .seconds(1), "Scan took too long: \(elapsed)")
    }
}
