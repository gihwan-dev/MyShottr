import Foundation

@MainActor
protocol DocumentWindowPresenting: AnyObject {
    func present(project: MyShottrProject)
}

@MainActor
final class RegionCaptureCoordinator {
    private let selector: any RegionSelecting
    private let capturer: any ScreenCapturing
    private let projectFactory: any NewProjectCreating
    private weak var windows: (any DocumentWindowPresenting)?
    private let now: () -> Date
    private var captureIsActive = false

    init(
        selector: any RegionSelecting,
        capturer: any ScreenCapturing,
        projectFactory: any NewProjectCreating,
        windows: any DocumentWindowPresenting,
        now: @escaping () -> Date = Date.init
    ) {
        self.selector = selector
        self.capturer = capturer
        self.projectFactory = projectFactory
        self.windows = windows
        self.now = now
    }

    @discardableResult
    func captureArea() async -> (any Error)? {
        guard !captureIsActive else {
            return CaptureError.captureAlreadyInProgress
        }

        captureIsActive = true
        defer {
            captureIsActive = false
        }

        do {
            let outcome = try await selector.selectRegion()
            guard case let .confirmed(selection) = outcome else {
                return nil
            }

            let artifact = try await capturer.capture(
                selection: selection
            )
            let project = try projectFactory.make(
                artifact: artifact,
                now: now()
            )
            windows?.present(project: project)
            return nil
        } catch {
            return error
        }
    }
}
