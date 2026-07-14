/// Per-application lifecycle-event preferences.
public struct ApplicationNotificationRule: Codable, Equatable, Sendable {
    public var application: NotificationApplication
    public var isMuted: Bool
    public var disabledProtocols: Set<TransportProtocol>
    public var disabledKinds: Set<PortEventRecord.Kind>
    public var includesTransientUDP: Bool

    public init(application: NotificationApplication) {
        self.application = application
        self.isMuted = false
        self.disabledProtocols = []
        self.disabledKinds = []
        self.includesTransientUDP = false
    }
}
