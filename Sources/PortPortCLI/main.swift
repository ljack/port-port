import Foundation
import PortPortCore

// MARK: - Argument parsing

let args = CommandLine.arguments.dropFirst()
let command = args.first(where: { !$0.hasPrefix("-") }) ?? "list"

func hasFlag(_ names: String...) -> Bool {
    args.contains(where: { names.contains($0) })
}

func flagValue(_ names: String...) -> String? {
    for (i, arg) in args.enumerated() {
        if names.contains(arg), i + 1 < args.count {
            return Array(args)[i + 1]
        }
        for name in names {
            if arg.hasPrefix("\(name)=") {
                return String(arg.dropFirst(name.count + 1))
            }
        }
    }
    return nil
}

let jsonOutput = hasFlag("--json", "-j")
let mineOnly = !hasFlag("--all", "-a")
let devOnly = hasFlag("--dev", "-d")
let forceKill = hasFlag("--force", "-f")

let techFilter: TechStack? = {
    guard let val = flagValue("--tech", "-t") else { return nil }
    return TechStack.allCases.first { $0.rawValue.lowercased() == val.lowercased() }
}()

// MARK: - Help

func printUsage() {
    let usage = """
    \(Terminal.bold("port-port-cli")) — monitor TCP/UDP listening ports

    \(Terminal.bold("USAGE"))
      port-port-cli [command] [options]

    \(Terminal.bold("COMMANDS"))
      list              List all listening ports (default)
      watch             Interactive TUI with live updates
      info <port>       Detailed info for a specific port
      kill <port>       Kill process on a port
      restart <port>    Restart a stopped app from history
      history           Show port history

    \(Terminal.bold("OPTIONS"))
      --json, -j        Output as JSON
      --all, -a         Show all ports (default: current user only)
      --dev, -d         Show only dev servers
      --tech <stack>    Filter by tech stack (node.js, python, go, etc.)
      --force, -f       Use SIGKILL instead of SIGTERM (with kill)
      --help, -h        Show this help
    """
    print(usage)
}

// MARK: - Dispatch

if hasFlag("--help", "-h") {
    printUsage()
    exit(0)
}

switch command {
case "list", "ls":
    Commands.list(mine: mineOnly, dev: devOnly, tech: techFilter, json: jsonOutput)

case "watch", "w":
    let tui = TUI()
    tui.run()

case "info", "i":
    guard let portArg = Array(args).dropFirst().first(where: { !$0.hasPrefix("-") }),
          let port = UInt16(portArg) else {
        fputs("Usage: port-port-cli info <port>\n", stderr)
        exit(1)
    }
    Commands.info(port: port, json: jsonOutput)

case "kill":
    guard let portArg = Array(args).dropFirst().first(where: { !$0.hasPrefix("-") }),
          let port = UInt16(portArg) else {
        fputs("Usage: port-port-cli kill <port>\n", stderr)
        exit(1)
    }
    Commands.killPort(port, force: forceKill)

case "restart":
    guard let portArg = Array(args).dropFirst().first(where: { !$0.hasPrefix("-") }),
          let port = UInt16(portArg) else {
        fputs("Usage: port-port-cli restart <port>\n", stderr)
        exit(1)
    }
    Commands.restart(port: port)

case "history", "hist":
    Commands.history(json: jsonOutput)

default:
    fputs("Unknown command: \(command)\n", stderr)
    printUsage()
    exit(1)
}
