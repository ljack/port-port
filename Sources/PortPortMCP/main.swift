import Foundation
import PortPortCore

// MCP stdio transport: reads JSON-RPC messages from stdin (one per line),
// dispatches to MCPHandler, and writes responses to stdout.

// Disable stdout buffering so responses are sent immediately
setbuf(stdout, nil)

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty else { continue }

    guard let data = line.data(using: .utf8) else { continue }

    if let response = MCPHandler.handle(data) {
        FileHandle.standardOutput.write(response)
    }
}
