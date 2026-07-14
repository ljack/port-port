/// Persistable notification rules with quiet defaults for transient UDP sockets.
public struct NotificationPolicy: Codable, Equatable, Sendable {
    public var rules: [String: ApplicationNotificationRule]

    public init(rules: [String: ApplicationNotificationRule] = [:]) {
        self.rules = rules
    }

    public func rule(for application: NotificationApplication) -> ApplicationNotificationRule {
        rules[application.id] ?? ApplicationNotificationRule(application: application)
    }

    public func allows(
        application: NotificationApplication,
        protocol transportProtocol: TransportProtocol,
        port: UInt16,
        kind: PortEventRecord.Kind
    ) -> Bool {
        let rule = rule(for: application)
        guard !rule.isMuted else { return false }
        guard !rule.disabledProtocols.contains(transportProtocol) else { return false }
        guard !rule.disabledKinds.contains(kind) else { return false }

        if transportProtocol == .udp, Self.isTransientPort(port), !rule.includesTransientUDP {
            return false
        }
        return true
    }

    public static func isTransientPort(_ port: UInt16) -> Bool {
        port >= 49_152
    }
}
