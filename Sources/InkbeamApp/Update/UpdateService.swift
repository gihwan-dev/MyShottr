import Sparkle

@MainActor
protocol UpdateServing: AnyObject {
    var canCheckForUpdates: Bool { get }
    func start() throws
    func checkForUpdates() throws
}

@MainActor
protocol StandardUpdaterControlling: AnyObject {
    var canCheckForUpdates: Bool { get }
    func startUpdater()
    func checkForUpdates(_ sender: Any?)
}

extension SPUStandardUpdaterController: StandardUpdaterControlling {
    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }
}

enum UpdateServiceError: Error, Equatable {
    case notStarted
}

@MainActor
final class UpdateService: UpdateServing {
    private let controller: any StandardUpdaterControlling
    private let configuration: UpdateConfiguration
    private let diagnostics: UpdateDiagnostics
    private var started = false

    init(
        controller: any StandardUpdaterControlling,
        configuration: UpdateConfiguration,
        diagnostics: UpdateDiagnostics = .live
    ) {
        self.controller = controller
        self.configuration = configuration
        self.diagnostics = diagnostics
    }

    static func live(info: [String: Any]) throws -> UpdateService {
        let configuration = try UpdateConfiguration(info: info)
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        return UpdateService(
            controller: controller,
            configuration: configuration
        )
    }

    var canCheckForUpdates: Bool {
        started && controller.canCheckForUpdates
    }

    func start() throws {
        guard !started else {
            return
        }
        try configuration.validate()
        controller.startUpdater()
        started = true
        diagnostics.record(.started(channel: configuration.channel))
    }

    func checkForUpdates() throws {
        guard started else {
            throw UpdateServiceError.notStarted
        }
        diagnostics.record(
            .manualCheckStarted(host: configuration.appcastHost)
        )
        controller.checkForUpdates(nil)
    }
}
