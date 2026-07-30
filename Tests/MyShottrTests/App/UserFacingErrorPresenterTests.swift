import AppKit
import CoreGraphics
import XCTest
@testable import MyShottr

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
                .captureFailed("ScreenCaptureKit stopped"),
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
            let viewModel = MyShottrUserFacingError.capture(error).viewModel
            XCTAssertEqual(viewModel.title, title)
            XCTAssertEqual(viewModel.primaryAction, action)
            XCTAssertFalse(viewModel.message.isEmpty)
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
            let viewModel = MyShottrUserFacingError
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
            let viewModel = MyShottrUserFacingError.inbox(error).viewModel
            XCTAssertEqual(viewModel.title, title)
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
            XCTAssertFalse(viewModel.message.isEmpty)
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
            let viewModel = MyShottrUserFacingError
                .editorBridge(error)
                .viewModel
            XCTAssertEqual(viewModel.title, title)
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
            XCTAssertFalse(viewModel.message.isEmpty)
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
            let viewModel = MyShottrUserFacingError
                .editorProtocol(error)
                .viewModel
            XCTAssertEqual(viewModel.title, title)
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
            XCTAssertFalse(viewModel.message.isEmpty)
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
            (
                .unsupportedAnnotationSchemaVersion(3),
                "Project Version Is Not Supported"
            ),
            (.invalidAnnotationJSON, "Project Could Not Be Opened"),
            (.invalidPNG, "Project Could Not Be Opened"),
            (.sourceDimensionsMismatch, "Project Could Not Be Opened"),
        ]

        for (error, title) in cases {
            let viewModel = MyShottrUserFacingError.project(error).viewModel
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
            MyShottrUserFacingError.projectSave.viewModel.title,
            "Project Could Not Be Saved"
        )
        XCTAssertEqual(
            MyShottrUserFacingError.projectSave.viewModel.primaryAction,
            .dismiss
        )
        XCTAssertEqual(
            MyShottrUserFacingError.pngExport.viewModel.title,
            "PNG Could Not Be Exported"
        )
        XCTAssertEqual(
            MyShottrUserFacingError.pngExport.viewModel.primaryAction,
            .dismiss
        )
        XCTAssertEqual(
            MyShottrUserFacingError
                .clipboard(.writeFailed)
                .viewModel
                .title,
            "Image Could Not Be Copied"
        )

        for error in compositeCases {
            let viewModel = MyShottrUserFacingError
                .compositeTransfer(error)
                .viewModel
            XCTAssertEqual(viewModel.title, "Image Transfer Failed")
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
            XCTAssertFalse(viewModel.message.isEmpty)
        }
    }

    func testShortcutAndChromeRegistrationErrorsHaveExhaustiveMappings() {
        let shortcut = MyShottrUserFacingError
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
            let viewModel = MyShottrUserFacingError
                .chromeRegistration(error)
                .viewModel
            XCTAssertEqual(viewModel.title, "Chrome Setup Could Not Be Completed")
            XCTAssertEqual(
                viewModel.primaryAction,
                .openChromeSetupInstructions
            )
            XCTAssertFalse(viewModel.message.isEmpty)
        }
    }

    func testRecoveryErrorsHaveExhaustiveMappings() {
        let storeCases: [RecoveryStoreError] = [
            .invalidRoot,
            .invalidPackagePath("bad.myshottr"),
            .invalidPackage(
                UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                .invalidManifest
            ),
            .documentIdentifierMismatch(
                path: UUID(
                    uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
                )!,
                manifest: UUID(
                    uuidString: "11111111-2222-3333-4444-555555555555"
                )!
            ),
            .readFailed,
            .writeFailed(
                UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            ),
            .removeFailed(
                UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            ),
            .discardStageFailed(
                UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            ),
            .discardRollbackFailed,
            .discardRollbackConflict(
                UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            ),
            .discardCleanupFailed("transaction"),
            .invalidDiscardTransactionPath("transaction"),
        ]
        for error in storeCases {
            let viewModel = MyShottrUserFacingError
                .recoveryStore(error)
                .viewModel
            XCTAssertTrue(
                [
                    "Recovery Data Could Not Be Read",
                    "Recovery Data Could Not Be Updated",
                ].contains(viewModel.title)
            )
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
        }

        let coordinatorCases: [RecoveryCoordinatorError] = [
            .invalidSelection(
                UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            ),
            .restoreFailed(
                UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            ),
        ]
        for error in coordinatorCases {
            let viewModel = MyShottrUserFacingError
                .recoveryCoordinator(error)
                .viewModel
            XCTAssertEqual(viewModel.title, "Project Could Not Be Recovered")
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
        }

        let terminationCases: [SessionTerminationStateError] = [
            .invalidRoot,
            .invalidState,
            .writeFailed,
        ]
        for error in terminationCases {
            let viewModel = MyShottrUserFacingError
                .sessionTermination(error)
                .viewModel
            XCTAssertEqual(viewModel.title, "Recovery State Could Not Be Updated")
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
        }

        let issue = RecoveryScanIssue(
            entryName: "corrupt.myshottr",
            error: .invalidPackagePath("corrupt.myshottr")
        )
        let issueViewModel = MyShottrUserFacingError
            .recoveryScanIssue(issue)
            .viewModel
        XCTAssertEqual(
            issueViewModel.title,
            "Recovery Data Could Not Be Read"
        )
        XCTAssertTrue(issueViewModel.message.contains("corrupt.myshottr"))

        let documentCases: [DocumentSessionError] = [
            .invalidDocument,
            .noOpenDocument,
            .noStagedDocument,
            .recoverySnapshotUnavailable,
        ]
        for error in documentCases {
            let viewModel = MyShottrUserFacingError
                .documentSession(error)
                .viewModel
            XCTAssertEqual(
                viewModel.title,
                "Document Recovery Could Not Be Updated"
            )
            XCTAssertEqual(viewModel.primaryAction, .dismiss)
        }
    }

    func testContextWrappingProducesOneTypedErrorForEachFailureBoundary() {
        XCTAssertEqual(
            MyShottrUserFacingError
                .wrapping(
                    CaptureError.screenRecordingPermissionDenied,
                    context: .capture
                )
                .viewModel
                .primaryAction,
            .openScreenRecordingSettings
        )
        XCTAssertEqual(
            MyShottrUserFacingError
                .wrapping(
                    ProjectPackageError.invalidManifest,
                    context: .projectOpen
                )
                .viewModel
                .title,
            "Project Could Not Be Opened"
        )
        XCTAssertEqual(
            MyShottrUserFacingError
                .wrapping(
                    PendingCaptureInboxError.invalidPNG,
                    context: .chromeImport
                )
                .viewModel
                .title,
            "Chrome Capture Image Is Invalid"
        )
        XCTAssertEqual(
            MyShottrUserFacingError
                .wrapping(
                    CompositeTransferError.invalidPNG,
                    context: .pngExport
                )
                .viewModel
                .title,
            "Image Transfer Failed"
        )
        XCTAssertEqual(
            MyShottrUserFacingError
                .wrapping(
                    NSError(domain: "test", code: 1),
                    context: .projectSave
                )
                .viewModel
                .title,
            "Project Could Not Be Saved"
        )
        XCTAssertEqual(
            MyShottrUserFacingError
                .wrapping(
                    CaptureInboxCoordinatorError
                        .windowPresenterUnavailable,
                    context: .chromeImport
                )
                .viewModel
                .title,
            "Chrome Capture Could Not Be Opened"
        )
        XCTAssertEqual(
            MyShottrUserFacingError
                .wrapping(
                    SafePNGValidationError.imageTooLarge,
                    context: .chromeImport
                )
                .viewModel
                .title,
            "Chrome Capture Is Too Large"
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
}

@MainActor
private final class AlertPresentationRecorder {
    var sheetAlerts: [NSAlert] = []
    var sheetWindows: [NSWindow] = []
    var modalAlerts: [NSAlert] = []
    var modalResponse: NSApplication.ModalResponse =
        .alertFirstButtonReturn
    private var sheetCompletion:
        ((NSApplication.ModalResponse) -> Void)?

    var api: UserFacingAlertPresentation {
        UserFacingAlertPresentation(
            beginSheet: { [weak self] alert, window, completion in
                self?.sheetAlerts.append(alert)
                self?.sheetWindows.append(window)
                self?.sheetCompletion = completion
            },
            runModal: { [weak self] alert in
                self?.modalAlerts.append(alert)
                return self?.modalResponse ?? .abort
            }
        )
    }

    func completeSheet(with response: NSApplication.ModalResponse) {
        sheetCompletion?(response)
        sheetCompletion = nil
    }
}
