import AppKit
import Foundation

@MainActor
protocol UserFacingErrorPresenting {
    func present(
        _ error: MyShottrUserFacingError,
        from window: NSWindow?
    )
}

@MainActor
final class WeakWindowRegistry {
    private final class WeakWindow {
        weak var value: NSWindow?

        init(_ value: NSWindow) {
            self.value = value
        }
    }

    private var entries: [
        ObjectIdentifier: WeakWindow
    ] = [:]

    var isEmpty: Bool {
        entries.isEmpty
    }

    func insert(_ window: NSWindow) {
        prune()
        entries[ObjectIdentifier(window)] =
            WeakWindow(window)
    }

    func contains(_ window: NSWindow) -> Bool {
        prune()
        return entries[ObjectIdentifier(window)]?
            .value === window
    }

    func prune() {
        entries = entries.filter {
            $0.value.value != nil
        }
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
    private let closedWindows = WeakWindowRegistry()
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
        from window: NSWindow?
    ) {
        let viewModel = error.viewModel
        route(
            AlertRequest(viewModel: viewModel),
            from: window
        )
    }

    private func route(
        _ request: AlertRequest,
        from window: NSWindow?
    ) {
        closedWindows.prune()
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
        closedWindows.prune()
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
        closedWindows.prune()
        guard var queue = windowQueues[identifier],
              queue.isPresenting,
              !queue.pending.isEmpty
        else {
            windowQueues.removeValue(forKey: identifier)
            return
        }

        if queue.window.value.map(closedWindows.contains) == true
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
        closedWindows.prune()
        modalQueue.append(request)
        drainModalQueue()
    }

    private func drainModalQueue() {
        closedWindows.prune()
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
        perform(request.viewModel.primaryAction)
    }

    private func windowDidClose(_ window: NSWindow) {
        closedWindows.insert(window)
    }

    private func isClosed(_ window: NSWindow) -> Bool {
        closedWindows.contains(window)
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
        }
    }

    private func perform(
        _ action: UserFacingErrorAction
    ) {
        switch action {
        case .dismiss:
            return
        case .openScreenRecordingSettings:
            actions.openScreenRecordingSettings()
        case .openChromeSetupInstructions:
            actions.openChromeSetupInstructions()
        }
    }
}
