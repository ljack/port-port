import Darwin
import Foundation

/// Low-level terminal control using ANSI escape codes and termios
enum Terminal {
    nonisolated(unsafe) private static var originalTermios: termios?

    // MARK: - Raw mode

    static func enableRawMode() {
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        originalTermios = raw

        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_cc.16 = 0  // VMIN
        raw.c_cc.17 = 1  // VTIME (100ms)

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    static func disableRawMode() {
        guard var original = originalTermios else { return }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
    }

    // MARK: - Screen

    static func enterAlternateScreen() {
        write("\u{1b}[?1049h")
    }

    static func leaveAlternateScreen() {
        write("\u{1b}[?1049l")
    }

    static func hideCursor() {
        write("\u{1b}[?25l")
    }

    static func showCursor() {
        write("\u{1b}[?25h")
    }

    static func clearScreen() {
        write("\u{1b}[2J")
    }

    static func moveTo(row: Int, col: Int) {
        write("\u{1b}[\(row);\(col)H")
    }

    static func clearLine() {
        write("\u{1b}[2K")
    }

    // MARK: - Size

    static func size() -> (rows: Int, cols: Int) {
        var winsz = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &winsz) == 0 {
            return (Int(winsz.ws_row), Int(winsz.ws_col))
        }
        return (24, 80)
    }

    // MARK: - Input

    /// Read a single keypress (non-blocking, returns nil if nothing available)
    static func readKey() -> Key? {
        var char: UInt8 = 0
        let bytesRead = read(STDIN_FILENO, &char, 1)
        guard bytesRead == 1 else { return nil }

        if char == 0x1b {
            // Escape sequence
            var seq: [UInt8] = [0, 0]
            guard read(STDIN_FILENO, &seq[0], 1) == 1 else { return .escape }
            guard read(STDIN_FILENO, &seq[1], 1) == 1 else { return .escape }
            if seq[0] == 0x5b { // [
                switch seq[1] {
                case 0x41: return .arrowUp
                case 0x42: return .down
                case 0x43: return .right
                case 0x44: return .left
                default: return .escape
                }
            }
            return .escape
        }

        return .char(Character(UnicodeScalar(char)))
    }

    enum Key {
        case char(Character)
        case arrowUp, down, left, right
        case escape
    }

    // MARK: - Colors

    static func bold(_ str: String) -> String { "\u{1b}[1m\(str)\u{1b}[0m" }
    static func dim(_ str: String) -> String { "\u{1b}[2m\(str)\u{1b}[0m" }
    static func green(_ str: String) -> String { "\u{1b}[32m\(str)\u{1b}[0m" }
    static func red(_ str: String) -> String { "\u{1b}[31m\(str)\u{1b}[0m" }
    static func yellow(_ str: String) -> String { "\u{1b}[33m\(str)\u{1b}[0m" }
    static func blue(_ str: String) -> String { "\u{1b}[34m\(str)\u{1b}[0m" }
    static func cyan(_ str: String) -> String { "\u{1b}[36m\(str)\u{1b}[0m" }
    static func magenta(_ str: String) -> String { "\u{1b}[35m\(str)\u{1b}[0m" }
    static func gray(_ str: String) -> String { "\u{1b}[90m\(str)\u{1b}[0m" }
    static func bgGreen(_ str: String) -> String { "\u{1b}[42;30m\(str)\u{1b}[0m" }
    static func bgRed(_ str: String) -> String { "\u{1b}[41;37m\(str)\u{1b}[0m" }
    static func bgYellow(_ str: String) -> String { "\u{1b}[43;30m\(str)\u{1b}[0m" }
    static func bgBlue(_ str: String) -> String { "\u{1b}[44;37m\(str)\u{1b}[0m" }
    static func inverse(_ str: String) -> String { "\u{1b}[7m\(str)\u{1b}[0m" }

    // MARK: - Output

    static func write(_ str: String) {
        var data = Array(str.utf8)
        Darwin.write(STDOUT_FILENO, &data, data.count)
    }

    /// Write a full frame buffer at once (reduces flicker).
    /// Replaces \n with \r\n since OPOST is disabled in raw mode.
    static func flush(_ buffer: String) {
        write(buffer.replacingOccurrences(of: "\n", with: "\r\n"))
    }
}
