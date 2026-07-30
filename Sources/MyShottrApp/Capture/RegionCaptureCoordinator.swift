import Foundation

@MainActor
protocol DocumentWindowPresenting: AnyObject {
    func present(project: MyShottrProject) throws
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
    func captureArea() async -> MyShottrUserFacingError? {
        guard !captureIsActive else {
            return .capture(.captureAlreadyInProgress)
        }

        captureIsActive = true
        defer {
            captureIsActive = false
        }

        let outcome: RegionSelectionOutcome
        do {
            outcome = try await selector.selectRegion()
        } catch let error as CaptureError {
            return .capture(error)
        } catch {
            return .captureWorkflow(.selectionFailed)
        }
        guard case let .confirmed(selection) = outcome else {
            return nil
        }

        let artifact: CaptureArtifact
        do {
            artifact = try await capturer.capture(
                selection: selection
            )
        } catch let error as CaptureError {
            return .capture(error)
        } catch {
            return .capture(.screenCaptureKitFailed)
        }

        let project: MyShottrProject
        do {
            project = try projectFactory.make(
                artifact: artifact,
                now: now()
            )
        } catch {
            return .captureWorkflow(.projectCreationFailed)
        }

        guard let windows else {
            return .captureWorkflow(.windowPresenterUnavailable)
        }
        do {
            try windows.present(project: project)
        } catch {
            return .captureWorkflow(.windowPresentationFailed)
        }
        return nil
    }
}
