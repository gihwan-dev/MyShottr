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

enum CaptureInboxCoordinatorError: Error {
    case windowPresenterUnavailable
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
    private let reportError: (any Error) -> Void
    private var presentedStates:
        [UUID: PresentedInMemoryState] = [:]
    private var isObserving = false

    init(
        inbox: any PendingCaptureStoring,
        projectFactory: any NewProjectCreating,
        windows: any DocumentWindowPresenting,
        now: @escaping () -> Date = Date.init,
        notificationAPI: CaptureReadyNotificationAPI = .live,
        reportError: @escaping (any Error) -> Void = {
            NSAlert(error: $0).runModal()
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

    func start() throws {
        if !isObserving {
            notificationAPI.addObserver(
                self,
                #selector(receiveCaptureReadyNotification(_:)),
                Self.captureReadyNotification
            )
            isObserving = true
        }
        try consumePendingCaptures()
    }

    func stop() {
        guard isObserving else {
            return
        }
        notificationAPI.removeObserver(self)
        isObserving = false
    }

    func consumePendingCaptures() throws {
        var firstError: (any Error)?

        do {
            for presented in try inbox.cleanupOnlyCaptures() {
                do {
                    _ = try inbox.cleanupPresented(presented)
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
        } catch {
            firstError = error
        }

        do {
            for staged in try inbox.pendingCaptures() {
                do {
                    try consume(id: staged.id)
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
        } catch {
            if firstError == nil {
                firstError = error
            }
        }

        if let firstError {
            throw firstError
        }
    }

    func consume(id: UUID) throws {
        if presentedStates[id] != nil {
            try finishPresentedCapture(id: id)
            return
        }

        guard let windows else {
            throw CaptureInboxCoordinatorError.windowPresenterUnavailable
        }
        let claim = try inbox.claim(id: id)
        let artifact = try CaptureArtifact(
            id: id,
            sourceKind: .chromeVisibleViewport,
            pngData: claim.pngData,
            scale: nil
        )
        let project = try projectFactory.make(
            artifact: artifact,
            now: now()
        )
        try windows.present(project: project)
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
            presented = try inbox.commitPresentation(claim)
            presentedStates[id] = .awaitingCleanup(presented)
        case .awaitingCleanup(let capture):
            presented = capture
        }

        _ = try inbox.cleanupPresented(presented)
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
        } catch PendingCaptureInboxError.captureNotFound {
            return
        } catch {
            reportError(error)
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
