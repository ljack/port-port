import Foundation
import PortPortCore

@MainActor
@Observable
final class NotificationPreferences {
    private static let defaultsKey = "notificationPolicy.v1"

    private(set) var policy: NotificationPolicy
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(NotificationPolicy.self, from: data) {
            self.policy = decoded
        } else {
            self.policy = NotificationPolicy()
        }
    }

    var savedApplications: [NotificationApplication] {
        policy.rules.values.map(\.application)
    }

    func rule(for application: NotificationApplication) -> ApplicationNotificationRule {
        policy.rule(for: application)
    }

    func allows(
        application: NotificationApplication,
        protocol transportProtocol: TransportProtocol,
        port: UInt16,
        kind: PortEventRecord.Kind
    ) -> Bool {
        policy.allows(
            application: application,
            protocol: transportProtocol,
            port: port,
            kind: kind
        )
    }

    func toggleMuted(for application: NotificationApplication) {
        updateRule(for: application) { $0.isMuted.toggle() }
    }

    func toggleProtocol(_ transportProtocol: TransportProtocol, for application: NotificationApplication) {
        updateRule(for: application) { rule in
            if !rule.disabledProtocols.insert(transportProtocol).inserted {
                rule.disabledProtocols.remove(transportProtocol)
            }
        }
    }

    func toggleKind(_ kind: PortEventRecord.Kind, for application: NotificationApplication) {
        updateRule(for: application) { rule in
            if !rule.disabledKinds.insert(kind).inserted {
                rule.disabledKinds.remove(kind)
            }
        }
    }

    func toggleTransientUDP(for application: NotificationApplication) {
        updateRule(for: application) { $0.includesTransientUDP.toggle() }
    }

    func reset(_ application: NotificationApplication) {
        policy.rules.removeValue(forKey: application.id)
        save()
    }

    private func updateRule(
        for application: NotificationApplication,
        change: (inout ApplicationNotificationRule) -> Void
    ) {
        var rule = policy.rule(for: application)
        change(&rule)
        policy.rules[application.id] = rule
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(policy) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
