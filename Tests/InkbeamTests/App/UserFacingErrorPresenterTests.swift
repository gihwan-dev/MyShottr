import AppKit
import CoreGraphics
import XCTest
@testable import Inkbeam

@MainActor
final class UserFacingErrorPresenterTests: XCTestCase {
    func testCaptureErrorsHaveExhaustiveActionableMappings() {
        let cases: [(CaptureError, String, UserFacingErrorAction)] = [
            (
                .screenRecordingPermissionDenied,
                "Screen Recording Permission Required",
                .openScreenRecordingSettings
            ),
            (
                .displayUnavailable(CGDirectDisplayID(42)),
                "Display Is No Longer Available",
                .dismiss
            ),
            (.emptySelection, "No Capture Area Selected", .dismiss),
            (
                .captureAlreadyInProgress,
                "Capture Already in Progress",
                .dismiss
            ),
            (
                .screenCaptureKitFailed,
                "Screen Capture Failed",
                .dismiss
            ),
            (
                .pngEncodingFailed,
                "Screenshot Could Not Be Created",
                .dismiss
            ),
        ]

        for (error, title, action) in cases {
            let viewModel = InkbeamUserFacingError.capture(error).viewModel
            XCTAssertEqual(viewModel.title, title)
            XCTAssertEqual(viewModel.primaryAction, action)
            XCTAssertFalse(viewModel.message.isEmpty)
        }
    }

    func testCaptureWorkflowFailuresKeepTheirBoundedPhase() {
        let cases: [(CaptureWorkflowError, String)] = [
            (
                .selectionFailed,
                "Capture Area Could Not Be Selected"
            ),
            (
                .projectCreationFailed,
                "Screenshot Document Could Not Be Created"
            ),
            (
                .windowPresenterUnavailable,
                "Screenshot Could Not Be Opened"
            ),
            (
                .windowPresentationFailed,
                "Screenshot Could Not Be Opened"
            ),
        ]

        for (error, expectedTitle) in cases {
            let viewModel = InkbeamUserFacingError
                .captureWorkflow(error)
                .viewModel
            XCTAssertEqual(viewModel.title, expectedTitle)
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
            XCTAssertFalse(viewModel.message.contains("raw-secret"))
        }
    }

    func testChromeHostAndProtocolErrorsHaveExhaustiveMappings() {
        let cases: [
            (
                ChromeNativeHostUserFacingError,
                String,
                UserFacingErrorAction
            )
        ] = [
            (
                .hostUnavailable,
                "Chrome Connection Is Not Ready",
                .openChromeSetupInstructions
            ),
            (
                .invalidMessage,
                "Chrome Capture Message Was Rejected",
                .dismiss
            ),
            (
                .unsupportedCaptureMode,
                "Capture Mode Is Not Supported",
                .dismiss
            ),
            (
                .invalidImage,
                "Chrome Capture Image Is Invalid",
                .dismiss
            ),
            (
                .imageTooLarge,
                "Chrome Capture Is Too Large",
                .dismiss
            ),
            (
                .stagingFailed,
                "Chrome Capture Could Not Be Staged",
                .dismiss
            ),
            (
                .appActivationFailed,
                "Chrome Capture Is Waiting",
                .dismiss
            ),
        ]

        for (error, title, action) in cases {
            let viewModel = InkbeamUserFacingError
                .chromeNativeHost(error)
                .viewModel
            XCTAssertEqual(viewModel.title, title)
            XCTAssertEqual(viewModel.primaryAction, action)
            XCTAssertFalse(viewModel.message.isEmpty)
        }
    }

    func testInboxErrorsHaveExhaustiveMappings() {
        let cases: [(PendingCaptureInboxError, String)] = [
            (.captureNotFound, "Chrome Capture Is No Longer Available"),
            (.insecureInboxRoot, "Chrome Capture Inbox Is Not Secure"),
            (.invalidEntry, "Chrome Capture Entry Was Rejected"),
            (.invalidPNG, "Chrome Capture Image Is Invalid"),
            (.imageTooLarge, "Chrome Capture Is Too Large"),
            (
                .systemCallFailed(name: "read", code: 5),
                "Chrome Capture Import Failed"
            ),
        ]

        for (error, title) in cases {
            let viewModel = InkbeamUserFacingError.inbox(error).viewModel
            XCTAssertEqual(viewModel.title, title)
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
            XCTAssertFalse(viewModel.message.isEmpty)
            XCTAssertFalse(
                viewModel.message
                    .localizedCaseInsensitiveContains("partial")
            )
        }
    }

    func testChromeImportPhasesNeverMisstateOpenedDocuments() {
        let cases: [
            (
                ChromeCaptureImportError,
                String,
                Bool
            )
        ] = [
            (
                .validation(.invalidPNG),
                "Chrome Capture Image Is Invalid",
                false
            ),
            (
                .validationFailed,
                "Chrome Capture Could Not Be Validated",
                false
            ),
            (
                .projectCreationFailed,
                "Chrome Capture Could Not Be Prepared",
                false
            ),
            (
                .windowPresenterUnavailable,
                "Chrome Capture Could Not Be Opened",
                false
            ),
            (
                .windowPresentationFailed,
                "Chrome Capture Could Not Be Opened",
                false
            ),
            (
                .durableCommitFailedAfterOpen,
                "Chrome Capture Opened; Inbox Commit Failed",
                true
            ),
            (
                .cleanupFailedAfterOpen,
                "Chrome Capture Opened; Cleanup Failed",
                true
            ),
            (
                .cleanupFailedAfterPriorOpen,
                "Chrome Capture Cleanup Failed",
                true
            ),
            (
                .scanFailed,
                "Chrome Capture Inbox Could Not Be Scanned",
                false
            ),
        ]

        for (error, title, documentOpened) in cases {
            let viewModel = InkbeamUserFacingError
                .chromeImport(error)
                .viewModel
            XCTAssertEqual(viewModel.title, title)
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
            XCTAssertEqual(
                viewModel.message.contains("document opened"),
                documentOpened
            )
            XCTAssertFalse(
                viewModel.message
                    .localizedCaseInsensitiveContains("partial")
            )
            if documentOpened {
                XCTAssertFalse(
                    viewModel.message.contains("not imported")
                )
            }
        }
    }

    func testEditorBridgeAndProtocolErrorsHaveExhaustiveMappings() {
        let bridgeCases: [(EditorBridgeError, String)] = [
            (.editorNotReady, "Editor Is Not Ready"),
            (.invalidMessage, "Editor Message Was Rejected"),
            (.invalidDocument, "Editor Document Is Invalid"),
            (.cancelled, "Editor Operation Was Cancelled"),
            (.timedOut, "Editor Operation Timed Out"),
        ]
        for (error, title) in bridgeCases {
            let viewModel = InkbeamUserFacingError
                .editorBridge(error)
                .viewModel
            XCTAssertEqual(viewModel.title, title)
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
            XCTAssertFalse(viewModel.message.isEmpty)
            XCTAssertFalse(
                viewModel.message
                    .localizedCaseInsensitiveContains("partial")
            )
        }

        let protocolCases: [(EditorBridgeEnvelopeError, String)] = [
            (
                .unsupportedProtocolVersion(2),
                "Editor Protocol Is Not Supported"
            ),
            (.payloadTooLarge, "Editor Message Is Too Large"),
            (.malformedMessage, "Editor Message Was Rejected"),
        ]
        for (error, title) in protocolCases {
            let viewModel = InkbeamUserFacingError
                .editorProtocol(error)
                .viewModel
            XCTAssertEqual(viewModel.title, title)
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
            XCTAssertFalse(viewModel.message.isEmpty)
            XCTAssertFalse(
                viewModel.message
                    .localizedCaseInsensitiveContains("partial")
            )
        }
    }

    func testProjectErrorsHaveExhaustiveMappingsWithoutPartialImport() {
        let cases: [(ProjectPackageError, String)] = [
            (.notDirectoryPackage, "Project Could Not Be Opened"),
            (
                .invalidMemberSet(["unexpected.txt"]),
                "Project Could Not Be Opened"
            ),
            (.invalidManifest, "Project Could Not Be Opened"),
            (
                .unsupportedFormatVersion(2),
                "Project Version Is Not Supported"
            ),
            (.invalidAnnotationJSON, "Project Could Not Be Opened"),
            (.invalidPNG, "Project Could Not Be Opened"),
            (.sourceDimensionsMismatch, "Project Could Not Be Opened"),
        ]

        for (error, title) in cases {
            let viewModel = InkbeamUserFacingError.project(error).viewModel
            XCTAssertEqual(viewModel.title, title)
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
            XCTAssertFalse(viewModel.message.localizedCaseInsensitiveContains(
                "partial"
            ))
        }
    }

    func testOutputErrorsHaveExhaustiveMappings() {
        let compositeCases: [CompositeTransferError] = [
            .temporaryFile,
            .invalidBase64,
            .unexpectedChunk(expected: 1, received: 2),
            .inconsistentChunkTotal(expected: 2, received: 3),
            .incomplete(expected: 2, received: 1),
            .invalidPNG,
            .invalidDimensions,
            .dimensionsMismatch(
                expectedWidth: 10,
                expectedHeight: 20,
                receivedWidth: 11,
                receivedHeight: 20
            ),
            .notFinished,
            .moveFailed,
        ]

        XCTAssertEqual(
            InkbeamUserFacingError.projectSave.viewModel.title,
            "Project Could Not Be Saved"
        )
        XCTAssertEqual(
            InkbeamUserFacingError.projectSave.viewModel.primaryAction,
            .dismiss
        )
        XCTAssertEqual(
            InkbeamUserFacingError.pngExport.viewModel.title,
            "PNG Could Not Be Exported"
        )
        XCTAssertEqual(
            InkbeamUserFacingError.pngExport.viewModel.primaryAction,
            .dismiss
        )
        XCTAssertEqual(
            InkbeamUserFacingError
                .clipboard(.writeFailed)
                .viewModel
                .title,
            "Image Could Not Be Copied"
        )

        for error in compositeCases {
            let viewModel = InkbeamUserFacingError
                .compositeTransfer(error)
                .viewModel
            XCTAssertEqual(viewModel.title, "Image Transfer Failed")
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
            XCTAssertFalse(viewModel.message.isEmpty)
            XCTAssertFalse(
                viewModel.message
                    .localizedCaseInsensitiveContains("partial")
            )
        }
    }

    func testShortcutAndChromeRegistrationErrorsHaveExhaustiveMappings() {
        let shortcut = InkbeamUserFacingError
            .globalShortcut(.registrationFailed(-9876))
            .viewModel
        XCTAssertEqual(shortcut.title, "Keyboard Shortcut Is Unavailable")
        XCTAssertEqual(shortcut.primaryAction, .dismiss)

        let registrationCases: [NativeMessagingRegistrarError] = [
            .invalidHelperPath,
            .missingPublicKeyResource,
            .systemCallFailed(name: "publish manifest", code: 5),
        ]
        for error in registrationCases {
            let viewModel = InkbeamUserFacingError
                .chromeRegistration(error)
                .viewModel
            XCTAssertEqual(viewModel.title, "Chrome Setup Could Not Be Completed")
            XCTAssertEqual(
                viewModel.primaryAction,
                .openChromeSetupInstructions
            )
            XCTAssertFalse(viewModel.message.isEmpty)
        }

        let rawRegistration = InkbeamUserFacingError
            .chromeRegistration(
                .systemCallFailed(
                    name: "raw-secret",
                    code: 5
                )
            )
            .viewModel
        XCTAssertFalse(
            rawRegistration.message.contains("raw-secret")
        )
        let rawInbox = InkbeamUserFacingError
            .inbox(
                .systemCallFailed(
                    name: "raw-secret",
                    code: 5
                )
            )
            .viewModel
        XCTAssertFalse(
            rawInbox.message.contains("raw-secret")
        )
    }

    func testDocumentSessionErrorsHaveExhaustiveMappings() {
        let documentCases: [DocumentSessionError] = [
            .invalidDocument,
            .noOpenDocument,
            .noStagedDocument,
        ]
        for error in documentCases {
            let viewModel = InkbeamUserFacingError
                .documentSession(error)
                .viewModel
            XCTAssertEqual(
                viewModel.title,
                "Document Could Not Be Updated"
            )
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
        }
    }

    func testContextWrappingProducesOneTypedErrorForEachFailureBoundary() {
        XCTAssertEqual(
            InkbeamUserFacingError
                .wrapping(
                    CaptureError.screenRecordingPermissionDenied,
                    context: .capture
                )
                .viewModel
                .primaryAction,
            .openScreenRecordingSettings
        )
        XCTAssertEqual(
            InkbeamUserFacingError
                .wrapping(
                    ProjectPackageError.invalidManifest,
                    context: .projectOpen
                )
                .viewModel
                .title,
            "Project Could Not Be Opened"
        )
        XCTAssertEqual(
            InkbeamUserFacingError
                .wrapping(
                    PendingCaptureInboxError.invalidPNG,
                    context: .chromeImport
                )
                .viewModel
                .title,
            "Chrome Capture Image Is Invalid"
        )
        XCTAssertEqual(
            InkbeamUserFacingError
                .wrapping(
                    CompositeTransferError.invalidPNG,
                    context: .pngExport
                )
                .viewModel
                .title,
            "Image Transfer Failed"
        )
        XCTAssertEqual(
            InkbeamUserFacingError
                .wrapping(
                    NSError(domain: "test", code: 1),
                    context: .projectSave
                )
                .viewModel
                .title,
            "Project Could Not Be Saved"
        )
        XCTAssertEqual(
            InkbeamUserFacingError
                .wrapping(
                    ChromeCaptureImportError
                        .windowPresenterUnavailable,
                    context: .chromeImport
                )
                .viewModel
                .title,
            "Chrome Capture Could Not Be Opened"
        )
        XCTAssertEqual(
            InkbeamUserFacingError
                .wrapping(
                    SafePNGValidationError.imageTooLarge,
                    context: .chromeImport
                )
                .viewModel
                .title,
            "Chrome Capture Is Too Large"
        )
    }

    func testCompositeTransferContextPreservesKnownErrorsAndMapsUnknownToApplication() {
        let cases: [(any Error, UserFacingErrorViewModel)] = [
            (
                CompositeTransferError.invalidPNG,
                InkbeamUserFacingError.compositeTransfer(
                    .invalidPNG
                ).viewModel
            ),
            (
                EditorBridgeEnvelopeError.malformedMessage,
                InkbeamUserFacingError.editorProtocol(
                    .malformedMessage
                ).viewModel
            ),
            (
                EditorBridgeError.invalidMessage,
                InkbeamUserFacingError.editorBridge(
                    .invalidMessage
                ).viewModel
            ),
            (
                CocoaError(.fileReadNoSuchFile),
                InkbeamUserFacingError.application.viewModel
            ),
        ]

        for (error, expectedViewModel) in cases {
            XCTAssertEqual(
                InkbeamUserFacingError.wrapping(
                    error,
                    context: .compositeTransfer
                ).viewModel,
                expectedViewModel
            )
        }
    }

    func testApplicationContextPreservesMoveToApplicationsMessage() {
        XCTAssertEqual(
            InkbeamUserFacingError.wrapping(
                ApplicationLaunchUserFacingError.moveToApplications,
                context: .application
            ).viewModel,
            UserFacingErrorViewModel(
                title: "Move Inkbeam to Applications",
                message:
                    "Move Inkbeam.app into an Applications folder, "
                    + "then relaunch it. Inkbeam did not start updates, "
                    + "Chrome capture import, or keyboard shortcuts.",
                primaryAction: .dismiss
            )
        )
    }

    func testPresenterUsesSheetOnlyForProvidedDocumentWindow() {
        let recorder = AlertPresentationRecorder()
        var openedSettings = 0
        let presenter = UserFacingErrorPresenter(
            presentation: recorder.api,
            actions: .init(
                openScreenRecordingSettings: {
                    openedSettings += 1
                },
                openChromeSetupInstructions: {},
                activateApplication: {}
            )
        )
        let documentWindow = NSWindow()

        presenter.present(
            .capture(.screenRecordingPermissionDenied),
            from: documentWindow
        )

        XCTAssertEqual(recorder.sheetWindows.count, 1)
        XCTAssertTrue(recorder.sheetWindows.first === documentWindow)
        XCTAssertEqual(recorder.modalAlerts.count, 0)
        XCTAssertEqual(
            recorder.sheetAlerts.first?.messageText,
            "Screen Recording Permission Required"
        )
        XCTAssertEqual(recorder.sheetAlerts.first?.buttons.count, 1)

        recorder.completeSheet(with: .alertFirstButtonReturn)
        XCTAssertEqual(openedSettings, 1)
    }

    func testPresenterUsesModalWithoutFabricatingAWindow() {
        let recorder = AlertPresentationRecorder()
        var activationCount = 0
        let presenter = UserFacingErrorPresenter(
            presentation: recorder.api,
            actions: .init(
                openScreenRecordingSettings: {},
                openChromeSetupInstructions: {},
                activateApplication: {
                    activationCount += 1
                }
            )
        )

        presenter.present(.pngExport, from: nil)

        XCTAssertTrue(recorder.sheetAlerts.isEmpty)
        XCTAssertEqual(recorder.modalAlerts.count, 1)
        XCTAssertEqual(activationCount, 1)
    }

    func testChromeSetupActionUsesInjectedLocalHelpAction() {
        let recorder = AlertPresentationRecorder()
        recorder.modalResponse = .alertFirstButtonReturn
        var openedChromeHelp = 0
        let presenter = UserFacingErrorPresenter(
            presentation: recorder.api,
            actions: .init(
                openScreenRecordingSettings: {},
                openChromeSetupInstructions: {
                    openedChromeHelp += 1
                },
                activateApplication: {}
            )
        )

        presenter.present(
            .chromeNativeHost(.hostUnavailable),
            from: nil
        )

        XCTAssertEqual(openedChromeHelp, 1)
    }

    func testSameWindowPresentsErrorsInFIFOOrder() {
        let recorder = AlertPresentationRecorder()
        let presenter = UserFacingErrorPresenter(
            presentation: recorder.api,
            actions: .noOp
        )
        let window = NSWindow()

        presenter.present(.pngExport, from: window)
        presenter.present(.projectSave, from: window)
        presenter.present(.clipboard(.writeFailed), from: window)

        XCTAssertEqual(
            recorder.sheetAlerts.map(\.messageText),
            ["PNG Could Not Be Exported"]
        )

        recorder.completeSheet(
            with: .alertFirstButtonReturn
        )
        XCTAssertEqual(
            recorder.sheetAlerts.map(\.messageText),
            [
                "PNG Could Not Be Exported",
                "Project Could Not Be Saved",
            ]
        )

        recorder.completeSheet(
            with: .alertFirstButtonReturn
        )
        XCTAssertEqual(
            recorder.sheetAlerts.map(\.messageText),
            [
                "PNG Could Not Be Exported",
                "Project Could Not Be Saved",
                "Image Could Not Be Copied",
            ]
        )
    }

    func testDifferentWindowsHaveIndependentSheetQueues() {
        let recorder = AlertPresentationRecorder()
        let presenter = UserFacingErrorPresenter(
            presentation: recorder.api,
            actions: .noOp
        )

        presenter.present(.pngExport, from: NSWindow())
        presenter.present(.projectSave, from: NSWindow())

        XCTAssertEqual(recorder.sheetAlerts.count, 2)
        XCTAssertEqual(
            recorder.sheetAlerts.map(\.messageText),
            [
                "PNG Could Not Be Exported",
                "Project Could Not Be Saved",
            ]
        )
    }

    func testModalPresentationDoesNotReenterRunModal() {
        let recorder = AlertPresentationRecorder()
        let presenter = UserFacingErrorPresenter(
            presentation: recorder.api,
            actions: .noOp
        )
        recorder.onRunModal = { alert in
            guard alert.messageText
                    == "PNG Could Not Be Exported"
            else {
                return
            }
            presenter.present(.projectSave, from: nil)
        }

        presenter.present(.pngExport, from: nil)

        XCTAssertEqual(recorder.maximumModalDepth, 1)
        XCTAssertEqual(
            recorder.modalAlerts.map(\.messageText),
            [
                "PNG Could Not Be Exported",
                "Project Could Not Be Saved",
            ]
        )
    }

    func testQueuedSheetUsesModalWhenItsWindowCloses() {
        let recorder = AlertPresentationRecorder()
        var activationCount = 0
        let presenter = UserFacingErrorPresenter(
            presentation: recorder.api,
            actions: .init(
                openScreenRecordingSettings: {},
                openChromeSetupInstructions: {},
                activateApplication: {
                    activationCount += 1
                }
            )
        )
        let window = NSWindow()
        presenter.present(.pngExport, from: window)
        presenter.present(.projectSave, from: window)

        NotificationCenter.default.post(
            name: NSWindow.willCloseNotification,
            object: window
        )
        recorder.completeSheet(
            with: .alertFirstButtonReturn
        )
        presenter.present(
            .clipboard(.writeFailed),
            from: window
        )

        XCTAssertEqual(recorder.sheetAlerts.count, 1)
        XCTAssertEqual(
            recorder.modalAlerts.map(\.messageText),
            [
                "Project Could Not Be Saved",
                "Image Could Not Be Copied",
            ]
        )
        XCTAssertEqual(activationCount, 2)
    }

    func testAlreadyClosedWindowUsesModalWithoutCreatingWindow() {
        let recorder = AlertPresentationRecorder()
        let presenter = UserFacingErrorPresenter(
            presentation: recorder.api,
            actions: .noOp
        )
        let window = NSWindow()
        NotificationCenter.default.post(
            name: NSWindow.willCloseNotification,
            object: window
        )

        presenter.present(.pngExport, from: window)

        XCTAssertTrue(recorder.sheetAlerts.isEmpty)
        XCTAssertEqual(
            recorder.modalAlerts.map(\.messageText),
            ["PNG Could Not Be Exported"]
        )
    }

    func testClosedWindowRegistryPrunesDeallocatedTombstones() {
        let registry = WeakWindowRegistry()
        weak var releasedWindow: NSWindow?

        autoreleasepool {
            let window = NSWindow()
            releasedWindow = window
            registry.insert(window)
            XCTAssertTrue(registry.contains(window))
        }

        XCTAssertNil(releasedWindow)
        registry.prune()
        XCTAssertTrue(registry.isEmpty)
    }
}

@MainActor
private final class AlertPresentationRecorder {
    var sheetAlerts: [NSAlert] = []
    var sheetWindows: [NSWindow] = []
    var modalAlerts: [NSAlert] = []
    var modalResponse: NSApplication.ModalResponse =
        .alertFirstButtonReturn
    var onRunModal: ((NSAlert) -> Void)?
    private(set) var maximumModalDepth = 0
    private var modalDepth = 0
    private var sheetCompletions: [
        (NSApplication.ModalResponse) -> Void
    ] = []

    var api: UserFacingAlertPresentation {
        UserFacingAlertPresentation(
            beginSheet: { [weak self] alert, window, completion in
                self?.sheetAlerts.append(alert)
                self?.sheetWindows.append(window)
                self?.sheetCompletions.append(completion)
            },
            runModal: { [weak self] alert in
                guard let self else {
                    return .abort
                }
                modalDepth += 1
                maximumModalDepth = max(
                    maximumModalDepth,
                    modalDepth
                )
                modalAlerts.append(alert)
                onRunModal?(alert)
                modalDepth -= 1
                return modalResponse
            }
        )
    }

    func completeSheet(with response: NSApplication.ModalResponse) {
        guard !sheetCompletions.isEmpty else {
            return
        }
        sheetCompletions.removeFirst()(response)
    }
}

@MainActor
private extension UserFacingErrorActions {
    static let noOp = UserFacingErrorActions(
        openScreenRecordingSettings: {},
        openChromeSetupInstructions: {},
        activateApplication: {}
    )
}
