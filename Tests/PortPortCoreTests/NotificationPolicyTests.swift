import Foundation
import Testing
@testable import PortPortCore

@Suite("NotificationPolicy Tests")
struct NotificationPolicyTests {
    private let homewizard = NotificationApplication(
        processName: "Python",
        processPath: "/opt/homebrew/bin/python3",
        workingDirectory: "/Users/test/_dev/homewizard"
    )

    @Test func workingDirectoryDefinesApplicationIdentity() {
        let upgradedPython = NotificationApplication(
            processName: "Python",
            processPath: "/opt/homebrew/bin/python3.15",
            workingDirectory: "/Users/test/_dev/homewizard/"
        )

        #expect(homewizard.id == upgradedPython.id)
        #expect(homewizard.name == "homewizard")
    }

    @Test func tcpServiceEventsAreAllowedByDefault() {
        let policy = NotificationPolicy()

        #expect(policy.allows(
            application: homewizard,
            protocol: .tcp,
            port: 5001,
            kind: .started
        ))
    }

    @Test func transientUDPEventsAreIgnoredByDefault() {
        let policy = NotificationPolicy()

        #expect(!policy.allows(
            application: homewizard,
            protocol: .udp,
            port: 51_731,
            kind: .started
        ))
    }

    @Test func applicationCanOptIntoTransientUDPEvents() {
        var policy = NotificationPolicy()
        var rule = policy.rule(for: homewizard)
        rule.includesTransientUDP = true
        policy.rules[homewizard.id] = rule

        #expect(policy.allows(
            application: homewizard,
            protocol: .udp,
            port: 51_731,
            kind: .stopped
        ))
    }

    @Test func protocolCanBeDisabledPerApplication() {
        var policy = NotificationPolicy()
        var rule = policy.rule(for: homewizard)
        rule.disabledProtocols.insert(.udp)
        policy.rules[homewizard.id] = rule

        #expect(!policy.allows(
            application: homewizard,
            protocol: .udp,
            port: 5_353,
            kind: .started
        ))
        #expect(policy.allows(
            application: homewizard,
            protocol: .tcp,
            port: 5_001,
            kind: .started
        ))
    }

    @Test func eventKindCanBeDisabledPerApplication() {
        var policy = NotificationPolicy()
        var rule = policy.rule(for: homewizard)
        rule.disabledKinds.insert(.stopped)
        policy.rules[homewizard.id] = rule

        #expect(!policy.allows(
            application: homewizard,
            protocol: .tcp,
            port: 5_001,
            kind: .stopped
        ))
        #expect(policy.allows(
            application: homewizard,
            protocol: .tcp,
            port: 5_001,
            kind: .started
        ))
    }

    @Test func mutedApplicationSuppressesEveryEvent() {
        var policy = NotificationPolicy()
        var rule = policy.rule(for: homewizard)
        rule.isMuted = true
        policy.rules[homewizard.id] = rule

        for kind in PortEventRecord.Kind.allCases {
            #expect(!policy.allows(
                application: homewizard,
                protocol: .tcp,
                port: 5_001,
                kind: kind
            ))
        }
    }

    @Test func rulesRoundTripThroughCodableStorage() throws {
        var policy = NotificationPolicy()
        var rule = policy.rule(for: homewizard)
        rule.disabledProtocols.insert(.udp)
        rule.disabledKinds.insert(.stopped)
        policy.rules[homewizard.id] = rule

        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(NotificationPolicy.self, from: data)

        #expect(decoded == policy)
    }

    @Test func oldEventRecordsDecodeWithoutTransportProtocol() throws {
        let json = """
        {
          "id": "9B0A3304-CCB7-44F0-99B9-D0AFFDD5AA00",
          "kind": "stopped",
          "timestamp": "2026-07-14T18:02:24Z",
          "port": 0,
          "processName": "3x Python",
          "processPath": "/opt/homebrew/bin/python3",
          "workingDirectory": "/Users/test/_dev/homewizard",
          "techStack": "Python",
          "commandArgs": ["python3", "web_monitor.py", "--port", "5001"]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let event = try decoder.decode(PortEventRecord.self, from: Data(json.utf8))

        #expect(event.transportProtocol == nil)
        #expect(event.workingDirectory == "/Users/test/_dev/homewizard")
    }
}
