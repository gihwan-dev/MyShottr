import AppKit
import Foundation

@MainActor
struct CaptureReadyNotificationAPI {
    let addObserver: (
        _ observer: Any,
        _ selector: Selector,
        _ name: Notification.Name
    ) -> Void
    let removeObserver: (_ observer: Any) -> Void

    static let live = CaptureReadyNotificationAPI(
        addObserver: { observer, selector, name in
            DistributedNotificationCenter.default().addObserver(
                observer,
                selector: selector,
                name: name,
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        },
        removeObserver: { observer in
            DistributedNotificationCenter.default().removeObserver(
                observer
            )
        }
    )
}

enum ChromeCaptureImportError: Error, Equatable {
    case validation(PendingCaptureInboxError)
    case validationFailed
    case projectCreationFailed
    case windowPresenterUnavailable
    case windowPresentationFailed
    case durableCommitFailedAfterOpen
    case cleanupFailedAfterOpen
    case cleanupFailedAfterPriorOpen
    case scanFailed
}

@MainActor
final class CaptureInboxCoordinator: NSObject {
    static let captureReadyNotification = Notification.Name(
        "com.myshottr.captureReady"
    )

    private let inbox: any PendingCaptureStoring
    private let projectFactory: any NewProjectCreating
    private weak var windows: (any DocumentWindowPresenting)?
    private let now: () -> Date
    private let notificationAPI: CaptureReadyNotificationAPI
    private let reportError: (MyShottrUserFacingError) -> Void
    private var presentedStates:
        [UUID: PresentedInMemoryState] = [:]
    private var isObserving = false

    init(
        inbox: any PendingCaptureStoring,
        projectFactory: any NewProjectCreating,
        windows: any DocumentWindowPresenting,
        now: @escaping () -> Date = Date.init,
        notificationAPI: CaptureReadyNotificationAPI = .live,
        reportError:
            @escaping (MyShottrUserFacingError) -> Void = {
                UserFacingErrorPresenter.shared.present(
                    $0,
                    from: nil
                )
        }
    ) {
        self.inbox = inbox
        self.projectFactory = projectFactory
        self.windows = windows
        self.now = now
        self.notificationAPI = notificationAPI
        self.reportError = reportError
        super.init()
    }

    func start() {
        if !isObserving {
            notificationAPI.addObserver(
                self,
                #selector(receiveCaptureReadyNotification(_:)),
                Self.captureReadyNotification
            )
            isObserving = true
        }
        consumePendingCaptures()
    }

    func stop() {
        guard isObserving else {
            return
        }
        notificationAPI.removeObserver(self)
        isObserving = false
    }

    func consumePendingCaptures() {
        do {
            for presented in try inbox.cleanupOnlyCaptures() {
                do {
                    _ = try inbox.cleanupPresented(presented)
                } catch {
                    reportError(
                        .chromeImport(
                            .cleanupFailedAfterPriorOpen
                        )
                    )
                }
            }
        } catch {
            reportError(.chromeImport(.scanFailed))
        }

        do {
            for staged in try inbox.pendingCaptures() {
                do {
                    try consume(id: staged.id)
                } catch let error as ChromeCaptureImportError {
                    reportError(.chromeImport(error))
                } catch {
                    reportError(
                        .chromeImport(.validationFailed)
                    )
                }
            }
        } catch {
            reportError(.chromeImport(.scanFailed))
        }
    }

    func consume(id: UUID) throws {
        if presentedStates[id] != nil {
            try finishPresentedCapture(id: id)
            return
        }

        guard let windows else {
            throw ChromeCaptureImportError
                .windowPresenterUnavailable
        }
        let claim: PendingCaptureClaim
        do {
            claim = try inbox.claim(id: id)
        } catch let error as PendingCaptureInboxError {
            throw ChromeCaptureImportError.validation(error)
        } catch {
            throw ChromeCaptureImportError.validationFailed
        }
        let artifact: CaptureArtifact
        do {
            artifact = try CaptureArtifact(
                id: id,
                sourceKind: .chromeVisibleViewport,
                pngData: claim.pngData,
                scale: nil
            )
        } catch SafePNGValidationError.invalidPNG {
            throw ChromeCaptureImportError.validation(.invalidPNG)
        } catch SafePNGValidationError.imageTooLarge {
            throw ChromeCaptureImportError.validation(.imageTooLarge)
        } catch {
            throw ChromeCaptureImportError.validationFailed
        }
        let project: MyShottrProject
        do {
            project = try projectFactory.make(
                artifact: artifact,
                now: now()
            )
        } catch {
            throw ChromeCaptureImportError
                .projectCreationFailed
        }
        do {
            try windows.present(project: project)
        } catch {
            throw ChromeCaptureImportError
                .windowPresentationFailed
        }
        presentedStates[id] = .awaitingCommit(claim)
        try finishPresentedCapture(id: id)
    }

    private func finishPresentedCapture(id: UUID) throws {
        guard let state = presentedStates[id] else {
            return
        }

        let presented: PresentedCapture
        switch state {
        case .awaitingCommit(let claim):
            do {
                presented = try inbox.commitPresentation(claim)
            } catch {
                throw ChromeCaptureImportError
                    .durableCommitFailedAfterOpen
            }
            presentedStates[id] = .awaitingCleanup(presented)
        case .awaitingCleanup(let capture):
            presented = capture
        }

        do {
            _ = try inbox.cleanupPresented(presented)
        } catch {
            throw ChromeCaptureImportError
                .cleanupFailedAfterOpen
        }
        presentedStates.removeValue(forKey: id)
    }

    func handleCaptureReadyNotification(_ notification: Notification) {
        guard
            notification.name == Self.captureReadyNotification,
            notification.userInfo == nil,
            let value = notification.object as? String,
            let id = UUID(uuidString: value),
            value == id.uuidString
        else {
            return
        }

        do {
            try consume(id: id)
        } catch ChromeCaptureImportError.validation(
            .captureNotFound
        ) {
            return
        } catch let error as ChromeCaptureImportError {
            reportError(.chromeImport(error))
        } catch {
            reportError(.chromeImport(.validationFailed))
        }
    }

    @objc
    private func receiveCaptureReadyNotification(
        _ notification: Notification
    ) {
        handleCaptureReadyNotification(notification)
    }
}

private enum PresentedInMemoryState {
    case awaitingCommit(PendingCaptureClaim)
    case awaitingCleanup(PresentedCapture)
}
