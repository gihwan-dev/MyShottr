import OSLog

enum UpdateDiagnosticEvent: Equatable {
    case started(channel: UpdateChannel)
    case manualCheckStarted(host: UpdateAppcastHost)
}

@MainActor
struct UpdateDiagnostics {
    private static let logger = Logger(
        subsystem: "dev.gihwan.inkbeam",
        category: "updates"
    )

    private let recorder: (UpdateDiagnosticEvent) -> Void

    init(_ recorder: @escaping (UpdateDiagnosticEvent) -> Void) {
        self.recorder = recorder
    }

    func record(_ event: UpdateDiagnosticEvent) {
        recorder(event)
    }

    static let silent = UpdateDiagnostics { _ in }

    static let live = UpdateDiagnostics { event in
        switch event {
        case let .started(channel):
            logger.notice(
                "Updater started channel=\(channel.rawValue, privacy: .public)"
            )
        case let .manualCheckStarted(host):
            logger.notice(
                "Manual update check started host=\(host.rawValue, privacy: .public)"
            )
        }
    }
}
