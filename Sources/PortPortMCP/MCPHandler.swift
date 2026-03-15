import Foundation

/// Routes JSON-RPC 2.0 messages and builds MCP protocol responses
enum MCPHandler: Sendable {

    /// Process a single JSON-RPC request and return the response bytes (with newline).
    /// Returns nil for notifications (no id).
    static func handle(_ data: Data) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return errorResponse(id: nil, code: -32700, message: "Parse error")
        }

        let id = json["id"]  // may be Int, String, or nil (notification)
        let method = json["method"] as? String ?? ""
        let params = json["params"] as? [String: Any]

        switch method {
        case "initialize":
            return successResponse(id: id, result: initializeResult())

        case "notifications/initialized":
            // Notification, no response needed
            return nil

        case "tools/list":
            return successResponse(id: id, result: toolsListResult())

        case "tools/call":
            return handleToolCall(id: id, params: params)

        case "ping":
            return successResponse(id: id, result: [:] as [String: Any])

        default:
            return errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - Protocol responses

    private static func initializeResult() -> [String: Any] {
        [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": [:] as [String: Any]
            ] as [String: Any],
            "serverInfo": [
                "name": "port-port",
                "version": "1.0.0"
            ] as [String: Any]
        ]
    }

    private static func toolsListResult() -> [String: Any] {
        [
            "tools": [
                listPortsToolSchema(),
                killPortToolSchema(),
                portInfoToolSchema()
            ] as [[String: Any]]
        ]
    }

    private static func listPortsToolSchema() -> [String: Any] {
        [
            "name": "list_ports",
            "description": "List all listening TCP and UDP ports on this machine. "
                + "Returns a JSON array of port information including port number, protocol, "
                + "PID, process name, path, working directory, tech stack, and command arguments.",
            "inputSchema": [
                "type": "object",
                "properties": [:] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    }

    private static func killPortToolSchema() -> [String: Any] {
        [
            "name": "kill_port",
            "description": "Kill the process listening on the specified port by sending SIGTERM.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "port": [
                        "type": "number",
                        "description": "The port number to kill the process on"
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["port"]
            ] as [String: Any]
        ] as [String: Any]
    }

    private static func portInfoToolSchema() -> [String: Any] {
        [
            "name": "port_info",
            "description": "Get detailed information about the process listening on a specific port.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "port": [
                        "type": "number",
                        "description": "The port number to get information about"
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["port"]
            ] as [String: Any]
        ] as [String: Any]
    }

    // MARK: - Tool dispatch

    private static func handleToolCall(id: Any?, params: [String: Any]?) -> Data? {
        guard let toolName = params?["name"] as? String else {
            return errorResponse(id: id, code: -32602, message: "Missing tool name")
        }

        let arguments = params?["arguments"] as? [String: Any] ?? [:]

        let text: String
        switch toolName {
        case "list_ports":
            text = MCPTools.listPorts()

        case "kill_port":
            guard let portNum = extractPort(from: arguments) else {
                return toolResult(id: id, text: "{\"error\": \"Missing or invalid 'port' argument\"}", isError: true)
            }
            text = MCPTools.killPort(portNum)

        case "port_info":
            guard let portNum = extractPort(from: arguments) else {
                return toolResult(id: id, text: "{\"error\": \"Missing or invalid 'port' argument\"}", isError: true)
            }
            text = MCPTools.portInfo(portNum)

        default:
            return toolResult(id: id, text: "{\"error\": \"Unknown tool: \(toolName)\"}", isError: true)
        }

        return toolResult(id: id, text: text, isError: false)
    }

    private static func extractPort(from arguments: [String: Any]) -> UInt16? {
        if let portDouble = arguments["port"] as? Double {
            let portInt = Int(portDouble)
            guard portInt > 0, portInt <= 65535 else { return nil }
            return UInt16(portInt)
        }
        if let portInt = arguments["port"] as? Int {
            guard portInt > 0, portInt <= 65535 else { return nil }
            return UInt16(portInt)
        }
        return nil
    }

    // MARK: - JSON-RPC response builders

    private static func toolResult(id: Any?, text: String, isError: Bool) -> Data? {
        var result: [String: Any] = [
            "content": [
                ["type": "text", "text": text] as [String: Any]
            ] as [[String: Any]]
        ]
        if isError {
            result["isError"] = true
        }
        return successResponse(id: id, result: result)
    }

    private static func successResponse(id: Any?, result: [String: Any]) -> Data? {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result
        ]
        if let id = id {
            response["id"] = id
        }
        return serialize(response)
    }

    private static func errorResponse(id: Any?, code: Int, message: String) -> Data? {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "error": [
                "code": code,
                "message": message
            ] as [String: Any]
        ]
        if let id = id {
            response["id"] = id
        }
        return serialize(response)
    }

    private static func serialize(_ dict: [String: Any]) -> Data? {
        guard var data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.sortedKeys]
        ) else {
            return nil
        }
        data.append(0x0A)  // newline
        return data
    }
}
