import SwiftUI
import PortPortCore

extension TechStack {
    var label: String {
        switch self {
        case .nodeJS: "JS"
        case .python: "Py"
        case .java: "Jv"
        case .ruby: "Rb"
        case .go: "Go"
        case .rust: "Rs"
        case .deno: "De"
        case .bun: "Bn"
        case .elixir: "Ex"
        case .dotnet: ".N"
        case .php: "PH"
        case .unknown: "?"
        }
    }

    var color: Color {
        switch self {
        case .nodeJS: .green
        case .python: .blue
        case .java: .orange
        case .ruby: .red
        case .go: .cyan
        case .rust: .brown
        case .deno: .mint
        case .bun: .pink
        case .elixir: .purple
        case .dotnet: .indigo
        case .php: .teal
        case .unknown: .gray
        }
    }
}

struct TechBadge: View {
    let techStack: TechStack
    var opacity: Double = 0.15

    var body: some View {
        Text(techStack.label)
            .font(.system(size: 14))
            .frame(width: 22, height: 22)
            .background(techStack.color.opacity(opacity), in: RoundedRectangle(cornerRadius: 5))
            .help(techStack.rawValue)
    }
}
