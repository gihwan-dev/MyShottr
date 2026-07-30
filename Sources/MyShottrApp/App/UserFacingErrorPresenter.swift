import AppKit
import Foundation

@MainActor
protocol UserFacingErrorPresenting {
    func present(
        _ error: MyShottrUserFacingError,
        from window: NSWindow?,
        retrySameOperation: (() -> Void)?
    )
}

@MainActor
extension UserFacingErrorPresenting {
    func present(
        _ error: MyShottrUserFacingError,
        from window: NSWindow?
    ) {
        present(
            error,
            from: window,
            retrySameOperation: nil
        )
    }
}

@MainActor
struct UserFacingAlertPresentation {
    let beginSheet: (
        NSAlert,
        NSWindow,
        @escaping (NSApplication.ModalResponse) -> Void
    ) -> Void
    let runModal: (NSAlert) -> NSApplication.ModalResponse

    static let live = UserFacingAlertPresentation(
        beginSheet: { alert, window, completion in
            alert.beginSheetModal(
                for: window,
                completionHandler: completion
            )
        },
        runModal: { alert in
            alert.runModal()
        }
    )
}

@MainActor
struct UserFacingErrorActions {
    let openScreenRecordingSettings: () -> Void
    let openChromeSetupInstructions: () -> Void
    let activateApplication: () -> Void

    static let live = UserFacingErrorActions(
        openScreenRecordingSettings: {
            guard let url = URL(
                string:
                    "x-apple.systempreferences:"
                    + "com.apple.preference.security"
                    + "?Privacy_ScreenCapture"
            ) else {
                return
            }
            NSWorkspace.shared.open(url)
        },
        openChromeSetupInstructions: {
            let alert = NSAlert()
            alert.messageText = "Connect MyShottr to Chrome"
            alert.informativeText = """
            1. Open MyShottr once so it can register its local Chrome helper.
            2. Open chrome://extensions and enable Developer mode.
            3. Load the unpacked MyShottr Chrome extension.
            4. Use the extension button on the page you want to capture.

            MyShottr keeps the captured PNG on this Mac.
            """
            alert.addButton(withTitle: "OK")
            alert.runModal()
        },
        activateApplication: {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    )
}

@MainActor
final class UserFacingErrorPresenter: UserFacingErrorPresenting {
    static let shared = UserFacingErrorPresenter()

    private final class WeakWindow {
        weak var value: NSWindow?

        init(_ value: NSWindow) {
            self.value = value
        }
    }

    private struct AlertRequest {
        let viewModel: UserFacingErrorViewModel
        let retrySameOperation: (() -> Void)?
    }

    private struct WindowAlertQueue {
        let window: WeakWindow
        var pending: [AlertRequest]
        var isPresenting: Bool
    }

    private let presentation: UserFacingAlertPresentation
    private let actions: UserFacingErrorActions
    private var windowQueues:
        [ObjectIdentifier: WindowAlertQueue] = [:]
    private var closedWindows:
        [ObjectIdentifier: WeakWindow] = [:]
    private var modalQueue: [AlertRequest] = []
    private var modalIsPresenting = false
    private nonisolated(unsafe) var windowCloseObserver:
        NSObjectProtocol?

    init(
        presentation: UserFacingAlertPresentation = .live,
        actions: UserFacingErrorActions = .live
    ) {
        self.presentation = presentation
        self.actions = actions
        windowCloseObserver =
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let window =
                        notification.object as? NSWindow
                else {
                    return
                }
                MainActor.assumeIsolated {
                    self?.windowDidClose(window)
                }
            }
    }

    deinit {
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(
                windowCloseObserver
            )
        }
    }

    func present(
        _ error: MyShottrUserFacingError,
        from window: NSWindow?,
        retrySameOperation: (() -> Void)?
    ) {
        let request = AlertRequest(
            viewModel: error.viewModel,
            retrySameOperation: retrySameOperation
        )
        if let window,
           !isClosed(window) {
            enqueue(request, for: window)
            return
        }
        enqueueModal(request)
    }

    private func enqueue(
        _ request: AlertRequest,
        for window: NSWindow
    ) {
        let identifier = ObjectIdentifier(window)
        var queue =
            windowQueues[identifier]
            ?? WindowAlertQueue(
                window: WeakWindow(window),
                pending: [],
                isPresenting: false
            )
        queue.pending.append(request)
        let shouldStart = !queue.isPresenting
        if shouldStart {
            queue.isPresenting = true
        }
        windowQueues[identifier] = queue
        if shouldStart {
            startNextSheet(for: identifier)
        }
    }

    private func startNextSheet(
        for identifier: ObjectIdentifier
    ) {
        guard var queue = windowQueues[identifier],
              queue.isPresenting,
              !queue.pending.isEmpty
        else {
            windowQueues.removeValue(forKey: identifier)
            return
        }

        if closedWindows[identifier]?.value != nil
            || queue.window.value == nil {
            let pending = queue.pending
            windowQueues.removeValue(forKey: identifier)
            for request in pending {
                enqueueModal(request)
            }
            return
        }

        let request = queue.pending.removeFirst()
        let window = queue.window.value
        windowQueues[identifier] = queue
        guard let window else {
            enqueueModal(request)
            startNextSheet(for: identifier)
            return
        }
        let alert = makeAlert(request.viewModel)
        presentation.beginSheet(
            alert,
            window
        ) { [weak self] response in
            self?.finishSheet(
                for: identifier,
                request: request,
                response: response
            )
        }
    }

    private func finishSheet(
        for identifier: ObjectIdentifier,
        request: AlertRequest,
        response: NSApplication.ModalResponse
    ) {
        handle(response, for: request)
        guard var queue = windowQueues[identifier] else {
            return
        }
        queue.isPresenting = false
        if queue.pending.isEmpty {
            windowQueues.removeValue(forKey: identifier)
            return
        }
        queue.isPresenting = true
        windowQueues[identifier] = queue
        startNextSheet(for: identifier)
    }

    private func enqueueModal(_ request: AlertRequest) {
        modalQueue.append(request)
        drainModalQueue()
    }

    private func drainModalQueue() {
        guard !modalIsPresenting else {
            return
        }
        modalIsPresenting = true
        defer {
            modalIsPresenting = false
        }
        while !modalQueue.isEmpty {
            let request = modalQueue.removeFirst()
            let alert = makeAlert(request.viewModel)
            actions.activateApplication()
            let response = presentation.runModal(alert)
            handle(response, for: request)
        }
    }

    private func handle(
        _ response: NSApplication.ModalResponse,
        for request: AlertRequest
    ) {
        guard response == .alertFirstButtonReturn else {
            return
        }
        perform(
            request.viewModel.primaryAction,
            retrySameOperation:
                request.retrySameOperation
        )
    }

    private func windowDidClose(_ window: NSWindow) {
        let identifier = ObjectIdentifier(window)
        closedWindows[identifier] = WeakWindow(window)
    }

    private func isClosed(_ window: NSWindow) -> Bool {
        let identifier = ObjectIdentifier(window)
        guard let reference = closedWindows[identifier] else {
            return false
        }
        guard let closedWindow = reference.value else {
            closedWindows.removeValue(forKey: identifier)
            return false
        }
        return closedWindow === window
    }

    private func makeAlert(
        _ viewModel: UserFacingErrorViewModel
    ) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = viewModel.title
        alert.informativeText = viewModel.message
        alert.addButton(
            withTitle: buttonTitle(
                for: viewModel.primaryAction
            )
        )
        return alert
    }

    private func buttonTitle(
        for action: UserFacingErrorAction
    ) -> String {
        switch action {
        case .dismiss:
            return "OK"
        case .openScreenRecordingSettings:
            return "Open System Settings"
        case .openChromeSetupInstructions:
            return "Show Chrome Setup"
        case .retrySameOperation:
            return "Retry"
        }
    }

    private func perform(
        _ action: UserFacingErrorAction,
        retrySameOperation: (() -> Void)?
    ) {
        switch action {
        case .dismiss:
            return
        case .openScreenRecordingSettings:
            actions.openScreenRecordingSettings()
        case .openChromeSetupInstructions:
            actions.openChromeSetupInstructions()
        case .retrySameOperation:
            retrySameOperation?()
        }
    }
}
