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
    private let presentation: UserFacingAlertPresentation
    private let actions: UserFacingErrorActions

    init(
        presentation: UserFacingAlertPresentation = .live,
        actions: UserFacingErrorActions = .live
    ) {
        self.presentation = presentation
        self.actions = actions
    }

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

    func present(
        _ error: MyShottrUserFacingError,
        from window: NSWindow?,
        retrySameOperation: (() -> Void)?
    ) {
        let viewModel = error.viewModel
        let alert = makeAlert(viewModel)
        let handleResponse = {
            [weak self] (response: NSApplication.ModalResponse) in
            guard response == .alertFirstButtonReturn else {
                return
            }
            self?.perform(
                viewModel.primaryAction,
                retrySameOperation: retrySameOperation
            )
        }

        if let window {
            presentation.beginSheet(
                alert,
                window,
                handleResponse
            )
            return
        }

        actions.activateApplication()
        handleResponse(presentation.runModal(alert))
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
