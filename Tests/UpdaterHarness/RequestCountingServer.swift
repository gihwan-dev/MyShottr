import Foundation

struct UpdaterRequestRecord: Equatable {
    let method: String
    let timestamp: Date
    let path: String
}

/// An observation seam for the policy model, not an HTTPS implementation.
///
/// Sparkle owns the real request, TLS, and signature-verification paths. This
/// recorder intentionally keeps only the metadata Inkbeam's policy exposes.
final class RequestCountingServer {
    private(set) var requests: [UpdaterRequestRecord] = []

    func recordAutomaticRequest(
        _ request: URLRequest,
        at timestamp: Date
    ) {
        guard let path = request.url?.path else {
            return
        }
        requests.append(
            UpdaterRequestRecord(
                method: request.httpMethod ?? "GET",
                timestamp: timestamp,
                path: path
            )
        )
    }
}

/// Models the documented Sparkle automatic-check lifecycle with an isolated
/// profile. It never instantiates Sparkle or opens a network connection.
@MainActor
final class SparkleAutomaticCheckLifecycleHarness {
    private enum DefaultsKey {
        static let launchCount = "sparkle.automaticCheck.launchCount"
        static let consent = "sparkle.automaticCheck.consent"
        static let lastRequest = "sparkle.automaticCheck.lastRequest"
    }

    private static let checkInterval: TimeInterval = 86_400
    private static let feedURL = URL(
        string: "https://gihwan-dev.github.io/inkbeam/appcast.xml"
    )!
    private let defaults: UserDefaults
    private let now: () -> Date
    private let server: RequestCountingServer

    init(
        defaults: UserDefaults,
        now: @escaping () -> Date,
        server: RequestCountingServer
    ) {
        self.defaults = defaults
        self.now = now
        self.server = server
    }

    func launch() -> Bool {
        let launchCount = defaults.integer(forKey: DefaultsKey.launchCount) + 1
        defaults.set(launchCount, forKey: DefaultsKey.launchCount)

        guard launchCount > 1 else {
            return false
        }
        guard defaults.object(forKey: DefaultsKey.consent) != nil else {
            return true
        }
        guard defaults.bool(forKey: DefaultsKey.consent) else {
            return false
        }
        guard shouldScheduleAutomaticRequest else {
            return false
        }

        recordAutomaticRequest()
        return false
    }

    func approveAutomaticChecks() {
        defaults.set(true, forKey: DefaultsKey.consent)
        recordAutomaticRequest()
    }

    func declineAutomaticChecks() {
        defaults.set(false, forKey: DefaultsKey.consent)
    }

    private var shouldScheduleAutomaticRequest: Bool {
        guard let lastRequest = defaults.object(
            forKey: DefaultsKey.lastRequest
        ) as? Date else {
            return true
        }
        return now().timeIntervalSince(lastRequest) >= Self.checkInterval
    }

    private func recordAutomaticRequest() {
        let timestamp = now()
        var request = URLRequest(url: Self.feedURL)
        request.httpMethod = "GET"
        server.recordAutomaticRequest(request, at: timestamp)
        defaults.set(timestamp, forKey: DefaultsKey.lastRequest)
    }
}
