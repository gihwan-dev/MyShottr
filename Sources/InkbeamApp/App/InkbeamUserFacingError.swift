import Foundation

enum UserFacingErrorAction: Equatable {
    case dismiss
    case openScreenRecordingSettings
    case openChromeSetupInstructions
}

struct UserFacingErrorViewModel: Equatable {
    let title: String
    let message: String
    let primaryAction: UserFacingErrorAction
}

enum ChromeNativeHostUserFacingError: Error, Equatable {
    case hostUnavailable
    case invalidMessage
    case unsupportedCaptureMode
    case invalidImage
    case imageTooLarge
    case stagingFailed
    case appActivationFailed
}

enum UserFacingErrorContext {
    case capture
    case chromeImport
    case chromeRegistration
    case projectOpen
    case projectSave
    case pngExport
    case compositeTransfer
    case clipboard
    case editorBridge
    case globalShortcut
    case application
}

enum InkbeamUserFacingError: Error {
    case capture(CaptureError)
    case captureWorkflow(CaptureWorkflowError)
    case chromeNativeHost(ChromeNativeHostUserFacingError)
    case chromeRegistration(NativeMessagingRegistrarError)
    case inbox(PendingCaptureInboxError)
    case chromeImport(ChromeCaptureImportError)
    case chromeImportBatch(ChromeCaptureImportBatchSummary)
    case chromeImportUnavailable
    case editorBridge(EditorBridgeError)
    case editorProtocol(EditorBridgeEnvelopeError)
    case project(ProjectPackageError)
    case projectSave
    case pngExport
    case clipboard(PNGClipboardWriterError)
    case compositeTransfer(CompositeTransferError)
    case globalShortcut(GlobalHotKeyError)
    case documentSession(DocumentSessionError)
    case application

    static func wrapping(
        _ error: any Error,
        context: UserFacingErrorContext
    ) -> InkbeamUserFacingError {
        switch context {
        case .capture:
            if let error = error as? CaptureError {
                return .capture(error)
            }
            return .capture(.screenCaptureKitFailed)

        case .chromeImport:
            if let error = error as? ChromeCaptureImportError {
                return .chromeImport(error)
            }
            if let error = error as? PendingCaptureInboxError {
                return .inbox(error)
            }
            if let error = error as? SafePNGValidationError {
                switch error {
                case .invalidPNG:
                    return .inbox(.invalidPNG)
                case .imageTooLarge:
                    return .inbox(.imageTooLarge)
                }
            }
            return .chromeImportUnavailable

        case .chromeRegistration:
            if let error = error as? NativeMessagingRegistrarError {
                return .chromeRegistration(error)
            }
            return .chromeNativeHost(.hostUnavailable)

        case .projectOpen:
            if let error = error as? ProjectPackageError {
                return .project(error)
            }
            return .project(.invalidManifest)

        case .projectSave:
            return .projectSave

        case .pngExport:
            if let error = error as? CompositeTransferError {
                return .compositeTransfer(error)
            }
            if let error = error as? EditorBridgeEnvelopeError {
                return .editorProtocol(error)
            }
            if let error = error as? EditorBridgeError {
                return .editorBridge(error)
            }
            return .pngExport

        case .compositeTransfer:
            if let error = error as? CompositeTransferError {
                return .compositeTransfer(error)
            }
            if let error = error as? EditorBridgeEnvelopeError {
                return .editorProtocol(error)
            }
            if let error = error as? EditorBridgeError {
                return .editorBridge(error)
            }
            return .application

        case .clipboard:
            if let error = error as? CompositeTransferError {
                return .compositeTransfer(error)
            }
            if let error = error as? EditorBridgeEnvelopeError {
                return .editorProtocol(error)
            }
            if let error = error as? EditorBridgeError {
                return .editorBridge(error)
            }
            if let error = error as? PNGClipboardWriterError {
                return .clipboard(error)
            }
            return .clipboard(.writeFailed)

        case .editorBridge:
            if let error = error as? EditorBridgeError {
                return .editorBridge(error)
            }
            if let error = error as? EditorBridgeEnvelopeError {
                return .editorProtocol(error)
            }
            return .editorBridge(.invalidMessage)

        case .globalShortcut:
            if let error = error as? GlobalHotKeyError {
                return .globalShortcut(error)
            }
            return .application

        case .application:
            return .application
        }
    }

    var title: String {
        viewModel.title
    }

    var viewModel: UserFacingErrorViewModel {
        switch self {
        case .capture(let error):
            return Self.captureViewModel(error)
        case .captureWorkflow(let error):
            return Self.captureWorkflowViewModel(error)
        case .chromeNativeHost(let error):
            return Self.chromeHostViewModel(error)
        case .chromeRegistration(let error):
            return Self.chromeRegistrationViewModel(error)
        case .inbox(let error):
            return Self.inboxViewModel(error)
        case .chromeImport(let error):
            return Self.chromeImportViewModel(error)
        case .chromeImportBatch(let summary):
            return Self.chromeImportBatchViewModel(summary)
        case .chromeImportUnavailable:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Could Not Be Opened",
                message:
                    "The captured image was not imported. "
                    + "The existing editor documents were not changed.",
                primaryAction: .dismiss
            )
        case .editorBridge(let error):
            return Self.editorBridgeViewModel(error)
        case .editorProtocol(let error):
            return Self.editorProtocolViewModel(error)
        case .project(let error):
            return Self.projectViewModel(error)
        case .projectSave:
            return UserFacingErrorViewModel(
                title: "Project Could Not Be Saved",
                message:
                    "Your document is still open and marked as modified. "
                    + "The selected destination was not replaced.",
                primaryAction: .dismiss
            )
        case .pngExport:
            return UserFacingErrorViewModel(
                title: "PNG Could Not Be Exported",
                message:
                    "The PNG was not written. "
                    + "Your editable document is unchanged.",
                primaryAction: .dismiss
            )
        case .clipboard(let error):
            switch error {
            case .writeFailed:
                return UserFacingErrorViewModel(
                    title: "Image Could Not Be Copied",
                    message:
                        "The image was not written to the clipboard. "
                        + "Your editable document is unchanged.",
                    primaryAction: .dismiss
                )
            }
        case .compositeTransfer(let error):
            return Self.compositeViewModel(error)
        case .globalShortcut(let error):
            switch error {
            case .registrationFailed:
                return UserFacingErrorViewModel(
                    title: "Keyboard Shortcut Is Unavailable",
                    message:
                        "Command-Shift-2 could not be registered. "
                        + "Capture Area remains available from the menu bar.",
                    primaryAction: .dismiss
                )
            }
        case .documentSession(let error):
            switch error {
            case .invalidDocument,
                 .noOpenDocument,
                 .noStagedDocument:
                return UserFacingErrorViewModel(
                    title: "Document Could Not Be Updated",
                    message:
                        "The document remains open and modified. "
                        + "Save the project before closing Inkbeam.",
                    primaryAction: .dismiss
                )
            }
        case .application:
            return UserFacingErrorViewModel(
                title: "Inkbeam Could Not Complete the Operation",
                message:
                    "The operation stopped without changing an existing "
                    + "document or destination.",
                primaryAction: .dismiss
            )
        }
    }

    private static func captureViewModel(
        _ error: CaptureError
    ) -> UserFacingErrorViewModel {
        switch error {
        case .cancelled:
            return UserFacingErrorViewModel(
                title: "Capture Cancelled",
                message: "The screen capture was cancelled before completion.",
                primaryAction: .dismiss
            )
        case .screenRecordingPermissionDenied:
            return UserFacingErrorViewModel(
                title: "Screen Recording Permission Required",
                message:
                    "Allow Inkbeam in System Settings > Privacy & "
                    + "Security > Screen Recording, then capture again.",
                primaryAction: .openScreenRecordingSettings
            )
        case .displayUnavailable:
            return UserFacingErrorViewModel(
                title: "Display Is No Longer Available",
                message:
                    "The selected display disconnected before the "
                    + "capture completed. No document was created.",
                primaryAction: .dismiss
            )
        case .emptySelection:
            return UserFacingErrorViewModel(
                title: "No Capture Area Selected",
                message:
                    "Drag a non-empty area before confirming the capture.",
                primaryAction: .dismiss
            )
        case .captureAlreadyInProgress:
            return UserFacingErrorViewModel(
                title: "Capture Already in Progress",
                message:
                    "Finish or cancel the current region selection first.",
                primaryAction: .dismiss
            )
        case .screenCaptureKitFailed:
            return UserFacingErrorViewModel(
                title: "Screen Capture Failed",
                message:
                    "ScreenCaptureKit could not capture the selected area. "
                    + "No document was created.",
                primaryAction: .dismiss
            )
        case .pngEncodingFailed:
            return UserFacingErrorViewModel(
                title: "Screenshot Could Not Be Created",
                message:
                    "The captured pixels could not be encoded as PNG. "
                    + "No document was created.",
                primaryAction: .dismiss
            )
        }
    }

    private static func captureWorkflowViewModel(
        _ error: CaptureWorkflowError
    ) -> UserFacingErrorViewModel {
        switch error {
        case .selectionFailed:
            return UserFacingErrorViewModel(
                title: "Capture Area Could Not Be Selected",
                message:
                    "The region selector stopped before an area was "
                    + "confirmed. No screenshot was captured.",
                primaryAction: .dismiss
            )
        case .projectCreationFailed:
            return UserFacingErrorViewModel(
                title: "Screenshot Document Could Not Be Created",
                message:
                    "The captured image could not be prepared as an editable "
                    + "document. No editor window was opened.",
                primaryAction: .dismiss
            )
        case .windowPresenterUnavailable:
            return UserFacingErrorViewModel(
                title: "Screenshot Could Not Be Opened",
                message:
                    "The document window presenter is no longer available. "
                    + "The screenshot was not opened.",
                primaryAction: .dismiss
            )
        case .windowPresentationFailed:
            return UserFacingErrorViewModel(
                title: "Screenshot Could Not Be Opened",
                message:
                    "The document window could not open the screenshot. "
                    + "No editor document was installed.",
                primaryAction: .dismiss
            )
        }
    }

    private static func chromeHostViewModel(
        _ error: ChromeNativeHostUserFacingError
    ) -> UserFacingErrorViewModel {
        switch error {
        case .hostUnavailable:
            return UserFacingErrorViewModel(
                title: "Chrome Connection Is Not Ready",
                message:
                    "Open Inkbeam once to register the Chrome connection, "
                    + "then try the Chrome capture again.",
                primaryAction: .openChromeSetupInstructions
            )
        case .invalidMessage:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Message Was Rejected",
                message:
                    "The native host rejected an invalid capture message. "
                    + "No image was imported.",
                primaryAction: .dismiss
            )
        case .unsupportedCaptureMode:
            return UserFacingErrorViewModel(
                title: "Capture Mode Is Not Supported",
                message:
                    "This release supports only the visible Chrome viewport. "
                    + "No other capture mode was used.",
                primaryAction: .dismiss
            )
        case .invalidImage:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Image Is Invalid",
                message:
                    "The native host rejected the image before importing it.",
                primaryAction: .dismiss
            )
        case .imageTooLarge:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Is Too Large",
                message:
                    "The image exceeds Inkbeam’s local import limit and "
                    + "was not staged.",
                primaryAction: .dismiss
            )
        case .stagingFailed:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Could Not Be Staged",
                message:
                    "The image was not published to Inkbeam’s local inbox.",
                primaryAction: .dismiss
            )
        case .appActivationFailed:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Is Waiting",
                message:
                    "The image is safely staged in Inkbeam’s local inbox. "
                    + "Open Inkbeam to import it.",
                primaryAction: .dismiss
            )
        }
    }

    private static func chromeRegistrationViewModel(
        _ error: NativeMessagingRegistrarError
    ) -> UserFacingErrorViewModel {
        let detail: String
        switch error {
        case .invalidHelperPath:
            detail = "The bundled native helper path is invalid."
        case .missingPublicKeyResource:
            detail = "The bundled Chrome extension identity is missing."
        case .systemCallFailed:
            detail = "A local Chrome registration step failed."
        }
        return UserFacingErrorViewModel(
            title: "Chrome Setup Could Not Be Completed",
            message:
                detail
                + " Native and project capture data remain unchanged.",
            primaryAction: .openChromeSetupInstructions
        )
    }

    private static func inboxViewModel(
        _ error: PendingCaptureInboxError
    ) -> UserFacingErrorViewModel {
        switch error {
        case .captureNotFound:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Is No Longer Available",
                message:
                    "The requested local inbox entry does not exist. "
                    + "No editor document was opened.",
                primaryAction: .dismiss
            )
        case .insecureInboxRoot:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Inbox Is Not Secure",
                message:
                    "Inkbeam refused to read the inbox because its "
                    + "ownership or permissions are unsafe.",
                primaryAction: .dismiss
            )
        case .invalidEntry:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Entry Was Rejected",
                message:
                    "The inbox entry failed path or file validation. "
                    + "No editor document was opened.",
                primaryAction: .dismiss
            )
        case .invalidPNG:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Image Is Invalid",
                message:
                    "The inbox image is not a valid PNG. "
                    + "No editor document was opened.",
                primaryAction: .dismiss
            )
        case .imageTooLarge:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Is Too Large",
                message:
                    "The inbox image exceeds Inkbeam’s local import limit. "
                    + "No editor document was opened.",
                primaryAction: .dismiss
            )
        case .systemCallFailed:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Import Failed",
                message:
                    "A local inbox operation failed. "
                    + "Existing documents were not changed.",
                primaryAction: .dismiss
            )
        }
    }

    private static func chromeImportViewModel(
        _ error: ChromeCaptureImportError
    ) -> UserFacingErrorViewModel {
        switch error {
        case .validation(let error):
            return inboxViewModel(error)
        case .validationFailed:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Could Not Be Validated",
                message:
                    "The local capture could not be validated and was not "
                    + "imported. The inbox entry remains available.",
                primaryAction: .dismiss
            )
        case .projectCreationFailed:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Could Not Be Prepared",
                message:
                    "The validated image could not be prepared as an editor "
                    + "document and was not imported.",
                primaryAction: .dismiss
            )
        case .windowPresenterUnavailable:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Could Not Be Opened",
                message:
                    "The document window presenter is unavailable, so the "
                    + "capture was not imported. The inbox entry remains.",
                primaryAction: .dismiss
            )
        case .windowPresentationFailed:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Could Not Be Opened",
                message:
                    "The editor window could not open, so the capture was "
                    + "not imported. The inbox entry remains.",
                primaryAction: .dismiss
            )
        case .editorLoad:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Is Waiting for Retry",
                message:
                    "The editor did not acknowledge the document, so the "
                    + "inbox handoff was not committed. The local inbox "
                    + "entry remains available.",
                primaryAction: .dismiss
            )
        case .editorProtocol:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Is Waiting for Retry",
                message:
                    "The editor rejected the document protocol, so the "
                    + "inbox handoff was not committed. The local inbox "
                    + "entry remains available.",
                primaryAction: .dismiss
            )
        case .durableCommitFailedAfterOpen:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Opened; Inbox Commit Failed",
                message:
                    "The editor document opened, but the inbox handoff was "
                    + "not committed. The local capture remains for retry "
                    + "without opening another window in this session.",
                primaryAction: .dismiss
            )
        case .cleanupFailedAfterOpen:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Opened; Cleanup Failed",
                message:
                    "The editor document opened and the inbox handoff was "
                    + "committed, but its local file remains for cleanup "
                    + "retry without opening another window.",
                primaryAction: .dismiss
            )
        case .cleanupFailedAfterPriorOpen:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Cleanup Failed",
                message:
                    "The editor document opened earlier, but its committed "
                    + "local inbox file remains for cleanup retry.",
                primaryAction: .dismiss
            )
        case .scanFailed:
            return UserFacingErrorViewModel(
                title: "Chrome Capture Inbox Could Not Be Scanned",
                message:
                    "Inkbeam could not enumerate one local inbox phase. "
                    + "Existing inbox files remain unchanged.",
                primaryAction: .dismiss
            )
        }
    }

    private static func chromeImportBatchViewModel(
        _ summary: ChromeCaptureImportBatchSummary
    ) -> UserFacingErrorViewModel {
        var phases: [String] = []
        if summary.notImportedCount > 0 {
            phases.append(
                summary.notImportedCount == 1
                    ? "1 capture was not imported."
                    : "\(summary.notImportedCount) captures were not imported."
            )
        }
        if summary.openedPendingCount > 0 {
            phases.append(
                summary.openedPendingCount == 1
                    ? "1 opened document still needs inbox commit or cleanup."
                    : "\(summary.openedPendingCount) opened documents still "
                        + "need inbox commit or cleanup."
            )
        }
        if summary.scanFailureCount > 0 {
            phases.append(
                summary.scanFailureCount == 1
                    ? "1 inbox scan phase could not be completed."
                    : "\(summary.scanFailureCount) inbox scan phases could "
                        + "not be completed."
            )
        }
        if summary.scanFailureCount > 0 {
            phases.append(
                "Any valid captures that were discovered were imported "
                    + "before this summary was shown."
            )
        } else {
            phases.append(
                "All other valid captures were imported before this summary "
                    + "was shown."
            )
        }
        return UserFacingErrorViewModel(
            title: "Chrome Capture Import Finished with Issues",
            message: phases.joined(separator: " "),
            primaryAction: .dismiss
        )
    }

    private static func editorBridgeViewModel(
        _ error: EditorBridgeError
    ) -> UserFacingErrorViewModel {
        switch error {
        case .editorNotReady:
            return UserFacingErrorViewModel(
                title: "Editor Is Not Ready",
                message:
                    "The editor did not finish loading. "
                    + "The native document state is unchanged.",
                primaryAction: .dismiss
            )
        case .invalidMessage:
            return UserFacingErrorViewModel(
                title: "Editor Message Was Rejected",
                message:
                    "Inkbeam rejected an invalid editor message and kept "
                    + "the current native document state.",
                primaryAction: .dismiss
            )
        case .invalidDocument:
            return UserFacingErrorViewModel(
                title: "Editor Document Is Invalid",
                message:
                    "The editor could not accept the document. "
                    + "The current document was not replaced.",
                primaryAction: .dismiss
            )
        case .cancelled:
            return UserFacingErrorViewModel(
                title: "Editor Operation Was Cancelled",
                message:
                    "The operation ended without replacing output or "
                    + "discarding document changes.",
                primaryAction: .dismiss
            )
        case .timedOut:
            return UserFacingErrorViewModel(
                title: "Editor Operation Timed Out",
                message:
                    "The editor did not respond in time. "
                    + "Your native document state is unchanged.",
                primaryAction: .dismiss
            )
        }
    }

    private static func editorProtocolViewModel(
        _ error: EditorBridgeEnvelopeError
    ) -> UserFacingErrorViewModel {
        switch error {
        case .unsupportedProtocolVersion:
            return UserFacingErrorViewModel(
                title: "Editor Protocol Is Not Supported",
                message:
                    "The editor message uses an unsupported protocol version "
                    + "and was rejected.",
                primaryAction: .dismiss
            )
        case .payloadTooLarge:
            return UserFacingErrorViewModel(
                title: "Editor Message Is Too Large",
                message:
                    "The editor message exceeded the local bridge limit "
                    + "and was rejected.",
                primaryAction: .dismiss
            )
        case .malformedMessage:
            return UserFacingErrorViewModel(
                title: "Editor Message Was Rejected",
                message:
                    "The editor message did not match the bridge protocol. "
                    + "The native document state is unchanged.",
                primaryAction: .dismiss
            )
        }
    }

    private static func projectViewModel(
        _ error: ProjectPackageError
    ) -> UserFacingErrorViewModel {
        switch error {
        case .unsupportedFormatVersion(let version):
            return UserFacingErrorViewModel(
                title: "Project Version Is Not Supported",
                message:
                    "Project format version \(version) is not supported. "
                    + "The project was not opened.",
                primaryAction: .dismiss
            )
        case .notDirectoryPackage,
             .invalidMemberSet,
             .invalidManifest,
             .invalidAnnotationJSON,
             .invalidPNG,
             .sourceDimensionsMismatch:
            return UserFacingErrorViewModel(
                title: "Project Could Not Be Opened",
                message:
                    "The project package is corrupt or invalid. "
                    + "No editor document was opened.",
                primaryAction: .dismiss
            )
        }
    }

    private static func compositeViewModel(
        _ error: CompositeTransferError
    ) -> UserFacingErrorViewModel {
        let detail: String
        switch error {
        case .temporaryFile:
            detail = "A secure temporary output file could not be created."
        case .invalidBase64:
            detail = "An output chunk contained invalid encoded data."
        case .unexpectedChunk:
            detail = "Output chunks arrived out of order."
        case .inconsistentChunkTotal:
            detail = "Output chunks reported inconsistent totals."
        case .incomplete:
            detail = "The editor did not send every output chunk."
        case .invalidPNG:
            detail = "The completed output is not a valid PNG."
        case .invalidDimensions:
            detail = "The completed output has invalid pixel dimensions."
        case .dimensionsMismatch:
            detail = "The completed output does not match the source size."
        case .notFinished:
            detail = "The output transfer did not finish."
        case .moveFailed:
            detail = "The validated PNG could not replace the destination."
        }
        return UserFacingErrorViewModel(
            title: "Image Transfer Failed",
            message:
                detail
                + " Temporary output was removed and the document is unchanged.",
            primaryAction: .dismiss
        )
    }

}
