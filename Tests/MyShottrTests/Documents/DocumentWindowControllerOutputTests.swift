import AppKit
import XCTest
@testable import MyShottr

@MainActor
final class DocumentWindowControllerOutputTests:
    TemporaryDirectoryTestCase
{
    func testCopyWritesExactCompletedPNGBeforeHidingWithoutClosing()
        async throws
    {
        let project = ProjectFixtures.project(text: "Copy success")
        let session = DocumentSession()
        try session.open(project: project)
        let completed = try makeCompletedTransfer()
        var events: [String] = []
        var requestedDirectories: [URL?] = []
        var clipboardPayloads: [Data] = []
        var statusSendCount = 0
        let presenter = OutputErrorPresenterSpy()
        let controller = try makeController(
            project: project,
            session: session,
            errorPresenter: presenter,
            compositeProvider: { destinationDirectory in
                events.append("composite.request")
                requestedDirectories.append(destinationDirectory)
                return completed.transfer
            },
            clipboardWriter: { data in
                events.append("clipboard.write")
                clipboardPayloads.append(data)
            },
            windowHider: {
                events.append("window.hide")
            },
            operationStatusSender: { _, _ in
                statusSendCount += 1
            }
        )
        let originalWindow = try XCTUnwrap(controller.window)
        var closeCount = 0
        controller.onClose = { closeCount += 1 }
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.copyComposite(nil))
        await waitUntil { events.count == 3 }

        XCTAssertEqual(
            events,
            [
                "composite.request",
                "clipboard.write",
                "window.hide",
            ]
        )
        XCTAssertEqual(requestedDirectories.count, 1)
        XCTAssertNil(requestedDirectories[0])
        XCTAssertEqual(clipboardPayloads, [ProjectFixtures.pngData])
        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(controller.window === originalWindow)
        XCTAssertTrue(session.isOpen)
        XCTAssertEqual(session.project, project)
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)
        XCTAssertEqual(statusSendCount, 0)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: completed.fileURL.path
            )
        )
    }

    func testCopyDataFailureSkipsClipboardAndHidePresentsCompositeErrorAndDiscards()
        async throws
    {
        let project = ProjectFixtures.project(text: "Copy data failure")
        let session = DocumentSession()
        try session.open(project: project)
        let unfinished = try makeUnfinishedTransfer()
        var clipboardWriteCount = 0
        var hideCount = 0
        var statusSendCount = 0
        let presenter = OutputErrorPresenterSpy()
        let controller = try makeController(
            project: project,
            session: session,
            errorPresenter: presenter,
            compositeProvider: { _ in unfinished.transfer },
            clipboardWriter: { _ in clipboardWriteCount += 1 },
            windowHider: { hideCount += 1 },
            operationStatusSender: { _, _ in
                statusSendCount += 1
            }
        )
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.copyComposite(nil))
        await waitUntil {
            presenter.presentedViewModels.count == 1
        }

        XCTAssertEqual(clipboardWriteCount, 0)
        XCTAssertEqual(hideCount, 0)
        XCTAssertEqual(statusSendCount, 0)
        XCTAssertEqual(
            presenter.presentedViewModels,
            [
                MyShottrUserFacingError.compositeTransfer(
                    .notFinished
                ).viewModel,
            ]
        )
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: unfinished.directory,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }

    func testCopyCompositeCreationFailureSkipsClipboardAndHideAndPresentsCompositeError()
        async throws
    {
        let project = ProjectFixtures.project(
            text: "Copy composite failure"
        )
        let session = DocumentSession()
        try session.open(project: project)
        var clipboardWriteCount = 0
        var hideCount = 0
        let presenter = OutputErrorPresenterSpy()
        let controller = try makeController(
            project: project,
            session: session,
            errorPresenter: presenter,
            compositeProvider: { _ in
                throw CompositeTransferError.invalidPNG
            },
            clipboardWriter: { _ in clipboardWriteCount += 1 },
            windowHider: { hideCount += 1 }
        )
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.copyComposite(nil))
        await waitUntil {
            presenter.presentedViewModels.count == 1
        }

        XCTAssertEqual(clipboardWriteCount, 0)
        XCTAssertEqual(hideCount, 0)
        XCTAssertEqual(
            presenter.presentedViewModels,
            [
                MyShottrUserFacingError.compositeTransfer(
                    .invalidPNG
                ).viewModel,
            ]
        )
    }

    func testCopyUnknownProviderFailurePresentsApplicationErrorWithoutClipboardStatusOrHide()
        async throws
    {
        let project = ProjectFixtures.project(
            text: "Copy unknown provider failure"
        )
        let session = DocumentSession()
        try session.open(project: project)
        var clipboardWriteCount = 0
        var statusSendCount = 0
        var hideCount = 0
        let presenter = OutputErrorPresenterSpy()
        let controller = try makeController(
            project: project,
            session: session,
            errorPresenter: presenter,
            compositeProvider: { _ in
                throw CocoaError(.fileReadNoSuchFile)
            },
            clipboardWriter: { _ in
                clipboardWriteCount += 1
            },
            windowHider: { hideCount += 1 },
            operationStatusSender: { _, _ in
                statusSendCount += 1
            }
        )
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.copyComposite(nil))
        await waitUntil {
            presenter.presentedViewModels.count == 1
        }

        XCTAssertEqual(
            presenter.presentedViewModels,
            [MyShottrUserFacingError.application.viewModel]
        )
        XCTAssertEqual(clipboardWriteCount, 0)
        XCTAssertEqual(statusSendCount, 0)
        XCTAssertEqual(hideCount, 0)
    }

    func testCopyClipboardFailureKeepsWindowVisiblePresentsClipboardErrorAndDiscards()
        async throws
    {
        let project = ProjectFixtures.project(
            text: "Copy clipboard failure"
        )
        let session = DocumentSession()
        try session.open(project: project)
        let completed = try makeCompletedTransfer()
        var clipboardWriteCount = 0
        var statusSendCount = 0
        var hideCount = 0
        let presenter = OutputErrorPresenterSpy()
        let controller = try makeController(
            project: project,
            session: session,
            errorPresenter: presenter,
            compositeProvider: { _ in completed.transfer },
            clipboardWriter: { _ in
                clipboardWriteCount += 1
                throw PNGClipboardWriterError.writeFailed
            },
            windowHider: { hideCount += 1 },
            operationStatusSender: { _, _ in
                statusSendCount += 1
            }
        )
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.copyComposite(nil))
        await waitUntil {
            presenter.presentedViewModels.count == 1
        }

        XCTAssertEqual(clipboardWriteCount, 1)
        XCTAssertEqual(statusSendCount, 0)
        XCTAssertEqual(hideCount, 0)
        XCTAssertEqual(
            presenter.presentedViewModels,
            [
                MyShottrUserFacingError.clipboard(
                    .writeFailed
                ).viewModel,
            ]
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: completed.fileURL.path
            )
        )
    }

    func testSuspendedCopyRejectsEverySecondOutputWithoutSideEffects()
        async throws
    {
        let project = ProjectFixtures.project(text: "Guard overlap")
        let session = DocumentSession()
        try session.open(project: project)
        let completed = try makeCompletedTransfer()
        let projectStore = OutputProjectStoreSpy()
        var suspendedContinuation:
            CheckedContinuation<CompositeTransfer, any Error>?
        var compositeRequestCount = 0
        var clipboardWriteCount = 0
        var projectURLRequestCount = 0
        var pngURLRequestCount = 0
        var snapshotRequestCount = 0
        var statusSendCount = 0
        var hideCount = 0
        let presenter = OutputErrorPresenterSpy()
        let controller = try DocumentWindowController(
            project: project,
            projectURL: nil,
            projectStore: projectStore,
            errorPresenter: presenter,
            testSession: session,
            annotationSnapshotProvider: {
                snapshotRequestCount += 1
                return project.annotationJSON
            },
            projectSaveURLProvider: {
                projectURLRequestCount += 1
                return nil
            },
            compositeProvider: { _ in
                compositeRequestCount += 1
                return try await withCheckedThrowingContinuation {
                    continuation in
                    suspendedContinuation = continuation
                }
            },
            clipboardWriter: { _ in
                clipboardWriteCount += 1
            },
            pngExportURLProvider: {
                pngURLRequestCount += 1
                return nil
            },
            operationStatusSender: { _, _ in
                statusSendCount += 1
            },
            windowHider: { hideCount += 1 },
            commandWindowPredicate: { _ in true }
        )
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.copyComposite(nil))
        await waitUntil { suspendedContinuation != nil }

        XCTAssertFalse(controller.copyComposite(nil))
        XCTAssertFalse(controller.saveProjectAction(nil))
        XCTAssertFalse(controller.exportComposite(nil))
        XCTAssertEqual(compositeRequestCount, 1)
        XCTAssertEqual(clipboardWriteCount, 0)
        XCTAssertEqual(projectURLRequestCount, 0)
        XCTAssertEqual(pngURLRequestCount, 0)
        XCTAssertEqual(snapshotRequestCount, 0)
        XCTAssertEqual(projectStore.saveCount, 0)
        XCTAssertEqual(statusSendCount, 0)
        XCTAssertEqual(hideCount, 0)
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)

        suspendedContinuation?.resume(
            returning: completed.transfer
        )
        await waitUntil { hideCount == 1 }
    }

    func testCopySuccessReleasesGuardForLaterCopy() async throws {
        let project = ProjectFixtures.project(text: "Guard success")
        let session = DocumentSession()
        try session.open(project: project)
        var transfers = [
            try makeCompletedTransfer(),
            try makeCompletedTransfer(),
        ]
        var hideCount = 0
        let controller = try makeController(
            project: project,
            session: session,
            errorPresenter: OutputErrorPresenterSpy(),
            compositeProvider: { _ in
                transfers.removeFirst().transfer
            },
            clipboardWriter: { _ in },
            windowHider: { hideCount += 1 }
        )
        let copyItem = try makeCopyToolbarItem(controller)
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.copyComposite(nil))
        await waitUntil {
            hideCount == 1
                && controller.validateToolbarItem(copyItem)
        }

        XCTAssertTrue(controller.copyComposite(nil))
        await waitUntil { hideCount == 2 }
    }

    func testCopyFailureReleasesGuardForLaterCopy() async throws {
        let project = ProjectFixtures.project(text: "Guard failure")
        let session = DocumentSession()
        try session.open(project: project)
        let completed = try makeCompletedTransfer()
        var requestCount = 0
        var hideCount = 0
        let presenter = OutputErrorPresenterSpy()
        let controller = try makeController(
            project: project,
            session: session,
            errorPresenter: presenter,
            compositeProvider: { _ in
                requestCount += 1
                if requestCount == 1 {
                    throw CompositeTransferError.invalidPNG
                }
                return completed.transfer
            },
            clipboardWriter: { _ in },
            windowHider: { hideCount += 1 }
        )
        let copyItem = try makeCopyToolbarItem(controller)
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.copyComposite(nil))
        await waitUntil {
            presenter.presentedViewModels.count == 1
                && controller.validateToolbarItem(copyItem)
        }

        XCTAssertTrue(controller.copyComposite(nil))
        await waitUntil { hideCount == 1 }
        XCTAssertEqual(requestCount, 2)
    }

    func testExportPanelCancellationReleasesGuardForLaterCopy()
        async throws
    {
        let project = ProjectFixtures.project(
            text: "Guard panel cancellation"
        )
        let session = DocumentSession()
        try session.open(project: project)
        let completed = try makeCompletedTransfer()
        var compositeRequestCount = 0
        var pngURLRequestCount = 0
        var statusSendCount = 0
        var hideCount = 0
        let presenter = OutputErrorPresenterSpy()
        var controller: DocumentWindowController!
        controller = try DocumentWindowController(
            project: project,
            projectURL: nil,
            errorPresenter: presenter,
            testSession: session,
            compositeProvider: { _ in
                compositeRequestCount += 1
                return completed.transfer
            },
            clipboardWriter: { _ in },
            pngExportURLProvider: {
                pngURLRequestCount += 1
                XCTAssertFalse(controller.exportComposite(nil))
                return nil
            },
            operationStatusSender: { _, _ in
                statusSendCount += 1
            },
            windowHider: { hideCount += 1 },
            commandWindowPredicate: { _ in true }
        )
        try await controller.waitForEditorLoad()

        XCTAssertFalse(controller.exportComposite(nil))

        XCTAssertEqual(pngURLRequestCount, 1)
        XCTAssertEqual(compositeRequestCount, 0)
        XCTAssertEqual(statusSendCount, 0)
        XCTAssertEqual(hideCount, 0)
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)
        XCTAssertTrue(controller.copyComposite(nil))
        await waitUntil { hideCount == 1 }
    }

    func testExportStartsBeforeCompositeMovesThenCompletesWithBasename()
        async throws
    {
        let project = ProjectFixtures.project(
            text: "Export success"
        )
        let session = DocumentSession()
        try session.open(project: project)
        let completed = try makeCompletedTransfer()
        let destinationURL = temporaryDirectory
            .appendingPathComponent(
                "Exports",
                isDirectory: true
            )
            .appendingPathComponent(
                "Annotated Final.png",
                isDirectory: false
            )
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var events: [String] = []
        var requestedDirectories: [URL?] = []
        var statuses: [OutputStatusRecord] = []
        var moveObservedAtCompletion = false
        var hideCount = 0
        let presenter = OutputErrorPresenterSpy()
        let controller = try DocumentWindowController(
            project: project,
            projectURL: nil,
            errorPresenter: presenter,
            testSession: session,
            compositeProvider: { directory in
                events.append("composite.request")
                requestedDirectories.append(directory)
                return completed.transfer
            },
            pngExportURLProvider: {
                events.append("destination.selected")
                return destinationURL
            },
            operationStatusSender: { requestID, status in
                statuses.append(
                    OutputStatusRecord(
                        requestID: requestID,
                        status: status
                    )
                )
                switch status {
                case .started(.export):
                    events.append("status.started")
                case .exportCompleted:
                    moveObservedAtCompletion =
                        FileManager.default.fileExists(
                            atPath: destinationURL.path
                        )
                        && (try? Data(contentsOf: destinationURL))
                            == ProjectFixtures.pngData
                    events.append("status.completed")
                default:
                    XCTFail("Unexpected Export status: \(status)")
                }
            },
            windowHider: { hideCount += 1 },
            commandWindowPredicate: { _ in true }
        )
        let originalWindow = try XCTUnwrap(controller.window)
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.exportComposite(nil))
        await waitUntil {
            statuses.count == 2
                || !presenter.presentedViewModels.isEmpty
        }

        XCTAssertEqual(
            events,
            [
                "destination.selected",
                "status.started",
                "composite.request",
                "status.completed",
            ]
        )
        XCTAssertEqual(
            requestedDirectories,
            [destinationURL.deletingLastPathComponent()]
        )
        XCTAssertEqual(
            statuses.map(\.status),
            [
                .started(.export),
                .exportCompleted(
                    displayName: "Annotated Final.png"
                ),
            ]
        )
        XCTAssertEqual(Set(statuses.map(\.requestID)).count, 1)
        XCTAssertTrue(moveObservedAtCompletion)
        XCTAssertEqual(
            try Data(contentsOf: destinationURL),
            ProjectFixtures.pngData
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: completed.fileURL.path
            )
        )
        XCTAssertEqual(hideCount, 0)
        XCTAssertTrue(controller.window === originalWindow)
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)
    }

    func testExportSanitizesOnlyDisplayBasenameBySwiftCharacterLimit()
        async throws
    {
        let project = ProjectFixtures.project(
            text: "Export display name"
        )
        let session = DocumentSession()
        try session.open(project: project)
        let completed = try makeCompletedTransfer()
        let combiningCharacter = "e\u{301}"
        let expectedDisplayName =
            String(repeating: "a", count: 119)
            + combiningCharacter
        let actualBasename =
            String(repeating: "a", count: 60)
            + "\n\t\u{0085}\u{0001}"
            + String(repeating: "a", count: 59)
            + combiningCharacter
            + "TAIL.png"
        let destinationURL = temporaryDirectory
            .appendingPathComponent(
                actualBasename,
                isDirectory: false
            )
        var statuses: [OutputStatusRecord] = []
        var requestedDirectories: [URL?] = []
        var hideCount = 0
        let presenter = OutputErrorPresenterSpy()
        let controller = try DocumentWindowController(
            project: project,
            projectURL: nil,
            errorPresenter: presenter,
            testSession: session,
            compositeProvider: { directory in
                requestedDirectories.append(directory)
                return completed.transfer
            },
            pngExportURLProvider: { destinationURL },
            operationStatusSender: { requestID, status in
                statuses.append(
                    OutputStatusRecord(
                        requestID: requestID,
                        status: status
                    )
                )
            },
            windowHider: { hideCount += 1 },
            commandWindowPredicate: { _ in true }
        )
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.exportComposite(nil))
        await waitUntil {
            statuses.count == 2
                || !presenter.presentedViewModels.isEmpty
        }

        XCTAssertEqual(
            statuses.map(\.status),
            [
                .started(.export),
                .exportCompleted(
                    displayName: expectedDisplayName
                ),
            ]
        )
        XCTAssertEqual(Set(statuses.map(\.requestID)).count, 1)
        XCTAssertEqual(expectedDisplayName.count, 120)
        XCTAssertFalse(
            expectedDisplayName.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
        )
        XCTAssertEqual(
            requestedDirectories,
            [destinationURL.deletingLastPathComponent()]
        )
        XCTAssertEqual(destinationURL.lastPathComponent, actualBasename)
        XCTAssertEqual(
            try Data(contentsOf: destinationURL),
            ProjectFixtures.pngData
        )
        let displayNameURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(expectedDisplayName)
        XCTAssertNotEqual(destinationURL, displayNameURL)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: displayNameURL.path
            )
        )
        XCTAssertEqual(hideCount, 0)
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)
    }

    func testExportCancellationAfterStartSendsSameUUIDCancelledWithoutNativeError()
        async throws
    {
        let project = ProjectFixtures.project(
            text: "Export cancellation"
        )
        let session = DocumentSession()
        try session.open(project: project)
        let destinationURL = temporaryDirectory
            .appendingPathComponent("Cancelled.png")
        var events: [String] = []
        var requestedDirectories: [URL?] = []
        var statuses: [OutputStatusRecord] = []
        var hideCount = 0
        let presenter = OutputErrorPresenterSpy {
            events.append("native.error")
        }
        let controller = try DocumentWindowController(
            project: project,
            projectURL: nil,
            errorPresenter: presenter,
            testSession: session,
            compositeProvider: { directory in
                events.append("composite.request")
                requestedDirectories.append(directory)
                throw CancellationError()
            },
            pngExportURLProvider: {
                events.append("destination.selected")
                return destinationURL
            },
            operationStatusSender: { requestID, status in
                statuses.append(
                    OutputStatusRecord(
                        requestID: requestID,
                        status: status
                    )
                )
                switch status {
                case .started(.export):
                    events.append("status.started")
                case .cancelled(.export):
                    events.append("status.cancelled")
                default:
                    XCTFail("Unexpected Export status: \(status)")
                }
            },
            windowHider: { hideCount += 1 },
            commandWindowPredicate: { _ in true }
        )
        let originalWindow = try XCTUnwrap(controller.window)
        let copyItem = try makeCopyToolbarItem(controller)
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.exportComposite(nil))
        await waitUntil {
            (statuses.count == 2
                || !presenter.presentedViewModels.isEmpty)
                && controller.validateToolbarItem(copyItem)
        }

        XCTAssertEqual(
            events,
            [
                "destination.selected",
                "status.started",
                "composite.request",
                "status.cancelled",
            ]
        )
        XCTAssertEqual(
            requestedDirectories,
            [destinationURL.deletingLastPathComponent()]
        )
        XCTAssertEqual(
            statuses.map(\.status),
            [.started(.export), .cancelled(.export)]
        )
        XCTAssertEqual(Set(statuses.map(\.requestID)).count, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destinationURL.path
            )
        )
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)
        XCTAssertEqual(hideCount, 0)
        XCTAssertTrue(controller.window === originalWindow)
    }

    func testExportFailureSendsSameUUIDFailedBeforeOneNativeErrorAndDiscards()
        async throws
    {
        let project = ProjectFixtures.project(
            text: "Export failure"
        )
        let session = DocumentSession()
        try session.open(project: project)
        let unfinished = try makeUnfinishedTransfer()
        let destinationURL = temporaryDirectory
            .appendingPathComponent("Failed.png")
        var events: [String] = []
        var statuses: [OutputStatusRecord] = []
        var hideCount = 0
        let presenter = OutputErrorPresenterSpy {
            events.append("native.error")
        }
        let controller = try DocumentWindowController(
            project: project,
            projectURL: nil,
            errorPresenter: presenter,
            testSession: session,
            compositeProvider: { _ in
                events.append("composite.request")
                return unfinished.transfer
            },
            pngExportURLProvider: {
                events.append("destination.selected")
                return destinationURL
            },
            operationStatusSender: { requestID, status in
                statuses.append(
                    OutputStatusRecord(
                        requestID: requestID,
                        status: status
                    )
                )
                switch status {
                case .started(.export):
                    events.append("status.started")
                case .failed(.export):
                    events.append("status.failed")
                default:
                    XCTFail("Unexpected Export status: \(status)")
                }
            },
            windowHider: { hideCount += 1 },
            commandWindowPredicate: { _ in true }
        )
        let originalWindow = try XCTUnwrap(controller.window)
        let copyItem = try makeCopyToolbarItem(controller)
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.exportComposite(nil))
        await waitUntil {
            (statuses.count == 2
                || presenter.presentedViewModels.count == 1)
                && controller.validateToolbarItem(copyItem)
        }

        XCTAssertEqual(
            events,
            [
                "destination.selected",
                "status.started",
                "composite.request",
                "status.failed",
                "native.error",
            ]
        )
        XCTAssertEqual(
            statuses.map(\.status),
            [.started(.export), .failed(.export)]
        )
        XCTAssertEqual(Set(statuses.map(\.requestID)).count, 1)
        XCTAssertEqual(
            presenter.presentedViewModels,
            [
                MyShottrUserFacingError.compositeTransfer(
                    .notFinished
                ).viewModel,
            ]
        )
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: unfinished.directory,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destinationURL.path
            )
        )
        XCTAssertEqual(hideCount, 0)
        XCTAssertTrue(controller.window === originalWindow)
    }

    func testUnsavedSaveDestinationCancellationHasNoStartedWorkAndReleasesGuard()
        async throws
    {
        let project = ProjectFixtures.project(
            text: "Unsaved cancellation"
        )
        let session = DocumentSession()
        try session.openUnsaved(project: project)
        let initialRevision = session.modificationRevision
        let store = OutputProjectStoreSpy()
        let presenter = OutputErrorPresenterSpy()
        var events: [String] = []
        var snapshotRequestCount = 0
        var statusSendCount = 0
        var hideCount = 0
        let controller = try DocumentWindowController(
            project: project,
            projectURL: nil,
            projectStore: store,
            errorPresenter: presenter,
            testSession: session,
            annotationSnapshotProvider: {
                events.append("snapshot.request")
                snapshotRequestCount += 1
                return project.annotationJSON
            },
            pendingChangesDecisionProvider: { .save },
            projectSaveURLProvider: {
                events.append("destination.cancelled")
                return nil
            },
            operationStatusSender: { _, _ in
                statusSendCount += 1
            },
            windowHider: { hideCount += 1 },
            commandWindowPredicate: { _ in true }
        )
        let copyItem = try makeCopyToolbarItem(controller)
        try await controller.waitForEditorLoad()

        let resolved = await controller
            .resolvePendingChangesForTermination()

        XCTAssertFalse(resolved)
        XCTAssertEqual(events, ["destination.cancelled"])
        XCTAssertEqual(
            session.modificationRevision,
            initialRevision
        )
        XCTAssertEqual(snapshotRequestCount, 0)
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertEqual(statusSendCount, 0)
        XCTAssertEqual(hideCount, 0)
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)
        XCTAssertTrue(controller.validateToolbarItem(copyItem))
    }

    func testUnsavedSaveSelectsDestinationBeforeStartedAndUpdatesWindowIdentity()
        async throws
    {
        let initial = ProjectFixtures.project(
            text: "Unsaved save initial"
        )
        let saved = ProjectFixtures.project(
            text: "Unsaved save snapshot"
        )
        let destination = temporaryDirectory.appendingPathComponent(
            "Chosen Project.myshottr",
            isDirectory: true
        )
        let session = DocumentSession()
        try session.openUnsaved(project: initial)
        let store = OutputProjectStoreSpy()
        var events: [String] = []
        var statuses: [OutputStatusRecord] = []
        var hideCount = 0
        var closeCount = 0
        store.onSave = { _, _ in
            events.append("project.store")
        }
        let presenter = OutputErrorPresenterSpy()
        let controller = try DocumentWindowController(
            project: initial,
            projectURL: nil,
            projectStore: store,
            errorPresenter: presenter,
            testSession: session,
            annotationSnapshotProvider: {
                events.append("snapshot.request")
                return saved.annotationJSON
            },
            projectSaveURLProvider: {
                events.append("destination.selected")
                return destination
            },
            closeWindow: { closeCount += 1 },
            operationStatusSender: { requestID, status in
                statuses.append(
                    OutputStatusRecord(
                        requestID: requestID,
                        status: status
                    )
                )
                switch status {
                case .started(.save):
                    events.append("status.started")
                case .saveCompleted:
                    events.append("status.completed")
                default:
                    XCTFail("Unexpected Save status: \(status)")
                }
            },
            windowHider: { hideCount += 1 },
            commandWindowPredicate: { _ in true }
        )
        try await controller.waitForEditorLoad()
        XCTAssertNil(controller.representedProjectURL)
        XCTAssertEqual(
            controller.window?.title,
            "Untitled MyShottr Project"
        )

        XCTAssertTrue(controller.saveProjectAction(nil))
        await waitUntil { statuses.count == 2 }

        XCTAssertEqual(
            events,
            [
                "destination.selected",
                "status.started",
                "snapshot.request",
                "project.store",
                "status.completed",
            ]
        )
        XCTAssertEqual(
            statuses.map(\.status),
            [.started(.save), .saveCompleted]
        )
        XCTAssertEqual(Set(statuses.map(\.requestID)).count, 1)
        XCTAssertEqual(store.savedURLs, [destination])
        XCTAssertEqual(
            store.savedProjects.map(\.annotationJSON),
            [saved.annotationJSON]
        )
        XCTAssertEqual(
            controller.representedProjectURL,
            destination
        )
        XCTAssertEqual(controller.window?.title, "Chosen Project")
        XCTAssertFalse(session.isModified)
        XCTAssertEqual(hideCount, 0)
        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)
    }

    func testExistingDestinationSaveOrdersStartedSnapshotStoreCompletionAndTerminalStatus()
        async throws
    {
        let initial = ProjectFixtures.project(text: "Save initial")
        let saved = ProjectFixtures.project(text: "Save snapshot")
        let destination = temporaryDirectory.appendingPathComponent(
            "Existing.myshottr",
            isDirectory: true
        )
        let session = DocumentSession()
        try session.open(project: initial)
        try session.applySnapshot(saved.annotationJSON)
        let store = OutputProjectStoreSpy()
        let presenter = OutputErrorPresenterSpy()
        var events: [String] = []
        var statuses: [OutputStatusRecord] = []
        var projectURLRequestCount = 0
        var hideCount = 0
        var closeCount = 0
        store.onSave = { _, _ in
            events.append("project.store")
            let existingHandler = session.onModifiedStateChange
            session.onModifiedStateChange = { modified in
                existingHandler?(modified)
                events.append(
                    modified
                        ? "session.superseded"
                        : "session.completed"
                )
            }
        }
        let controller = try DocumentWindowController(
            project: initial,
            projectURL: destination,
            projectStore: store,
            errorPresenter: presenter,
            testSession: session,
            annotationSnapshotProvider: {
                events.append("snapshot.request")
                return saved.annotationJSON
            },
            projectSaveURLProvider: {
                projectURLRequestCount += 1
                return nil
            },
            closeWindow: { closeCount += 1 },
            operationStatusSender: { requestID, status in
                statuses.append(
                    OutputStatusRecord(
                        requestID: requestID,
                        status: status
                    )
                )
                switch status {
                case .started(.save):
                    events.append("status.started")
                case .saveCompleted:
                    events.append("status.completed")
                default:
                    events.append("status.unexpected")
                }
            },
            windowHider: { hideCount += 1 },
            commandWindowPredicate: { _ in true }
        )
        let originalWindow = try XCTUnwrap(controller.window)
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.saveProjectAction(nil))
        await waitUntil { !session.isModified }

        XCTAssertEqual(
            events,
            [
                "status.started",
                "snapshot.request",
                "project.store",
                "session.completed",
                "status.completed",
            ]
        )
        XCTAssertEqual(
            statuses.map(\.status),
            [.started(.save), .saveCompleted]
        )
        XCTAssertEqual(Set(statuses.map(\.requestID)).count, 1)
        XCTAssertEqual(projectURLRequestCount, 0)
        XCTAssertEqual(store.savedURLs, [destination])
        XCTAssertEqual(
            store.savedProjects.map(\.annotationJSON),
            [saved.annotationJSON]
        )
        XCTAssertEqual(
            session.project?.annotationJSON,
            saved.annotationJSON
        )
        XCTAssertFalse(session.isModified)
        XCTAssertEqual(
            controller.representedProjectURL,
            destination
        )
        XCTAssertEqual(controller.window?.title, "Existing")
        XCTAssertTrue(controller.window === originalWindow)
        XCTAssertEqual(hideCount, 0)
        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)
    }

    func testSaveRevisionRaceStoresCapturedSnapshotAndSendsSameUUIDSuperseded()
        async throws
    {
        let initial = ProjectFixtures.project(text: "Race initial")
        let captured = ProjectFixtures.project(text: "Race captured")
        let latest = ProjectFixtures.project(text: "Race latest")
        let destination = temporaryDirectory.appendingPathComponent(
            "Race.myshottr",
            isDirectory: true
        )
        let session = DocumentSession()
        try session.open(project: initial)
        try session.applySnapshot(captured.annotationJSON)
        let store = OutputProjectStoreSpy()
        let presenter = OutputErrorPresenterSpy()
        var events: [String] = []
        var statuses: [OutputStatusRecord] = []
        var hideCount = 0
        store.onSave = { _, _ in
            events.append("project.store")
            let existingHandler = session.onModifiedStateChange
            session.onModifiedStateChange = { modified in
                existingHandler?(modified)
                events.append(
                    modified
                        ? "session.superseded"
                        : "session.completed"
                )
            }
        }
        let controller = try DocumentWindowController(
            project: initial,
            projectURL: destination,
            projectStore: store,
            errorPresenter: presenter,
            testSession: session,
            annotationSnapshotProvider: {
                events.append("snapshot.request")
                return captured.annotationJSON
            },
            operationStatusSender: { requestID, status in
                statuses.append(
                    OutputStatusRecord(
                        requestID: requestID,
                        status: status
                    )
                )
                switch status {
                case .started(.save):
                    events.append("status.started")
                    do {
                        try session.applySnapshot(
                            latest.annotationJSON
                        )
                    } catch {
                        XCTFail(
                            "Could not install the newer edit: \(error)"
                        )
                    }
                case .saveSuperseded:
                    events.append("status.superseded")
                default:
                    events.append("status.unexpected")
                }
            },
            windowHider: { hideCount += 1 },
            commandWindowPredicate: { _ in true }
        )
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.saveProjectAction(nil))
        await waitUntil {
            statuses.count == 2 || !session.isModified
        }

        XCTAssertEqual(
            events,
            [
                "status.started",
                "snapshot.request",
                "project.store",
                "session.superseded",
                "status.superseded",
            ]
        )
        XCTAssertEqual(
            statuses.map(\.status),
            [.started(.save), .saveSuperseded]
        )
        XCTAssertEqual(Set(statuses.map(\.requestID)).count, 1)
        XCTAssertEqual(store.savedURLs, [destination])
        XCTAssertEqual(
            store.savedProjects.map(\.annotationJSON),
            [captured.annotationJSON]
        )
        XCTAssertEqual(
            session.project?.annotationJSON,
            latest.annotationJSON
        )
        XCTAssertTrue(session.isModified)
        XCTAssertEqual(hideCount, 0)
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)
    }

    func testSaveCancellationAfterStartSendsSameUUIDCancelledWithoutNativeError()
        async throws
    {
        let project = ProjectFixtures.project(
            text: "Save cancellation"
        )
        let destination = temporaryDirectory.appendingPathComponent(
            "Cancelled.myshottr",
            isDirectory: true
        )
        let session = DocumentSession()
        try session.open(project: project)
        try session.markModified()
        let store = OutputProjectStoreSpy()
        var events: [String] = []
        var statuses: [OutputStatusRecord] = []
        var hideCount = 0
        var closeCount = 0
        let presenter = OutputErrorPresenterSpy {
            events.append("native.error")
        }
        let controller = try DocumentWindowController(
            project: project,
            projectURL: destination,
            projectStore: store,
            errorPresenter: presenter,
            testSession: session,
            annotationSnapshotProvider: {
                events.append("snapshot.request")
                throw CancellationError()
            },
            closeWindow: { closeCount += 1 },
            operationStatusSender: { requestID, status in
                statuses.append(
                    OutputStatusRecord(
                        requestID: requestID,
                        status: status
                    )
                )
                switch status {
                case .started(.save):
                    events.append("status.started")
                case .cancelled(.save):
                    events.append("status.cancelled")
                default:
                    events.append("status.unexpected")
                }
            },
            windowHider: { hideCount += 1 },
            commandWindowPredicate: { _ in true }
        )
        let copyItem = try makeCopyToolbarItem(controller)
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.saveProjectAction(nil))
        await waitUntil {
            statuses.count == 2
                || !presenter.presentedViewModels.isEmpty
        }

        XCTAssertEqual(
            events,
            [
                "status.started",
                "snapshot.request",
                "status.cancelled",
            ]
        )
        XCTAssertEqual(
            statuses.map(\.status),
            [.started(.save), .cancelled(.save)]
        )
        XCTAssertEqual(Set(statuses.map(\.requestID)).count, 1)
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertTrue(session.isModified)
        XCTAssertEqual(hideCount, 0)
        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(controller.validateToolbarItem(copyItem))
    }

    func testSaveFailureSendsSameUUIDFailedBeforeOneNativeError()
        async throws
    {
        let project = ProjectFixtures.project(text: "Save failure")
        let destination = temporaryDirectory.appendingPathComponent(
            "Failed.myshottr",
            isDirectory: true
        )
        let session = DocumentSession()
        try session.open(project: project)
        try session.markModified()
        let store = OutputProjectStoreSpy()
        var events: [String] = []
        var statuses: [OutputStatusRecord] = []
        var hideCount = 0
        var closeCount = 0
        let presenter = OutputErrorPresenterSpy {
            events.append("native.error")
        }
        let controller = try DocumentWindowController(
            project: project,
            projectURL: destination,
            projectStore: store,
            errorPresenter: presenter,
            testSession: session,
            annotationSnapshotProvider: {
                events.append("snapshot.request")
                throw OutputTestError.saveFailure
            },
            closeWindow: { closeCount += 1 },
            operationStatusSender: { requestID, status in
                statuses.append(
                    OutputStatusRecord(
                        requestID: requestID,
                        status: status
                    )
                )
                switch status {
                case .started(.save):
                    events.append("status.started")
                case .failed(.save):
                    events.append("status.failed")
                default:
                    events.append("status.unexpected")
                }
            },
            windowHider: { hideCount += 1 },
            commandWindowPredicate: { _ in true }
        )
        let copyItem = try makeCopyToolbarItem(controller)
        try await controller.waitForEditorLoad()

        XCTAssertTrue(controller.saveProjectAction(nil))
        await waitUntil {
            presenter.presentedViewModels.count == 1
        }

        XCTAssertEqual(
            events,
            [
                "status.started",
                "snapshot.request",
                "status.failed",
                "native.error",
            ]
        )
        XCTAssertEqual(
            statuses.map(\.status),
            [.started(.save), .failed(.save)]
        )
        XCTAssertEqual(Set(statuses.map(\.requestID)).count, 1)
        XCTAssertEqual(
            presenter.presentedViewModels,
            [MyShottrUserFacingError.projectSave.viewModel]
        )
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertTrue(session.isModified)
        XCTAssertEqual(hideCount, 0)
        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(controller.validateToolbarItem(copyItem))
    }

    func testClosePromptSaveContinuesCloseOnlyAfterFullySavedOutcome()
        async throws
    {
        let project = ProjectFixtures.project(text: "Close saved")
        let destination = temporaryDirectory.appendingPathComponent(
            "Close Saved.myshottr",
            isDirectory: true
        )
        let session = DocumentSession()
        try session.open(project: project)
        try session.markModified()
        let store = OutputProjectStoreSpy()
        let presenter = OutputErrorPresenterSpy()
        var statuses: [OutputStatusRecord] = []
        var closeCount = 0
        var hideCount = 0
        let controller = try DocumentWindowController(
            project: project,
            projectURL: destination,
            projectStore: store,
            errorPresenter: presenter,
            testSession: session,
            annotationSnapshotProvider: {
                project.annotationJSON
            },
            pendingChangesDecisionProvider: { .save },
            closeWindow: { closeCount += 1 },
            operationStatusSender: { requestID, status in
                statuses.append(
                    OutputStatusRecord(
                        requestID: requestID,
                        status: status
                    )
                )
            },
            windowHider: { hideCount += 1 },
            commandWindowPredicate: { _ in true }
        )
        let window = try XCTUnwrap(controller.window)
        try await controller.waitForEditorLoad()

        XCTAssertFalse(controller.windowShouldClose(window))
        await waitUntil { closeCount == 1 }

        XCTAssertEqual(
            statuses.map(\.status),
            [.started(.save), .saveCompleted]
        )
        XCTAssertEqual(Set(statuses.map(\.requestID)).count, 1)
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertFalse(session.isModified)
        XCTAssertEqual(hideCount, 0)
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)
    }

    func testClosePromptSupersededSaveKeepsWindowOpen()
        async throws
    {
        let initial = ProjectFixtures.project(
            text: "Close superseded initial"
        )
        let captured = ProjectFixtures.project(
            text: "Close superseded captured"
        )
        let latest = ProjectFixtures.project(
            text: "Close superseded latest"
        )
        let destination = temporaryDirectory.appendingPathComponent(
            "Close Superseded.myshottr",
            isDirectory: true
        )
        let session = DocumentSession()
        try session.open(project: initial)
        try session.applySnapshot(captured.annotationJSON)
        let store = OutputProjectStoreSpy()
        let presenter = OutputErrorPresenterSpy()
        var statuses: [OutputStatusRecord] = []
        var closeCount = 0
        let controller = try DocumentWindowController(
            project: initial,
            projectURL: destination,
            projectStore: store,
            errorPresenter: presenter,
            testSession: session,
            annotationSnapshotProvider: {
                captured.annotationJSON
            },
            pendingChangesDecisionProvider: { .save },
            closeWindow: { closeCount += 1 },
            operationStatusSender: { requestID, status in
                statuses.append(
                    OutputStatusRecord(
                        requestID: requestID,
                        status: status
                    )
                )
                if status == .started(.save) {
                    do {
                        try session.applySnapshot(
                            latest.annotationJSON
                        )
                    } catch {
                        XCTFail(
                            "Could not install the newer edit: \(error)"
                        )
                    }
                }
            },
            commandWindowPredicate: { _ in true }
        )
        let window = try XCTUnwrap(controller.window)
        try await controller.waitForEditorLoad()

        XCTAssertFalse(controller.windowShouldClose(window))
        await waitUntil { statuses.count == 2 }

        XCTAssertEqual(
            statuses.map(\.status),
            [.started(.save), .saveSuperseded]
        )
        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(
            store.savedProjects.map(\.annotationJSON),
            [captured.annotationJSON]
        )
        XCTAssertEqual(
            session.project?.annotationJSON,
            latest.annotationJSON
        )
        XCTAssertTrue(session.isModified)
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)
    }

    func testClosePromptDestinationCancellationKeepsWindowOpen()
        async throws
    {
        let project = ProjectFixtures.project(
            text: "Close before-start cancellation"
        )
        let session = DocumentSession()
        try session.openUnsaved(project: project)
        let store = OutputProjectStoreSpy()
        let presenter = OutputErrorPresenterSpy()
        var destinationRequestCount = 0
        var snapshotRequestCount = 0
        var statusSendCount = 0
        var closeCount = 0
        let controller = try DocumentWindowController(
            project: project,
            projectURL: nil,
            projectStore: store,
            errorPresenter: presenter,
            testSession: session,
            annotationSnapshotProvider: {
                snapshotRequestCount += 1
                return project.annotationJSON
            },
            pendingChangesDecisionProvider: { .save },
            projectSaveURLProvider: {
                destinationRequestCount += 1
                return nil
            },
            closeWindow: { closeCount += 1 },
            operationStatusSender: { _, _ in
                statusSendCount += 1
            },
            commandWindowPredicate: { _ in true }
        )
        let window = try XCTUnwrap(controller.window)
        let copyItem = try makeCopyToolbarItem(controller)
        try await controller.waitForEditorLoad()

        XCTAssertFalse(controller.windowShouldClose(window))
        await waitUntil {
            destinationRequestCount == 1
                && controller.validateToolbarItem(copyItem)
        }

        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(snapshotRequestCount, 0)
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertEqual(statusSendCount, 0)
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)
    }

    func testClosePromptCancellationAfterStartKeepsWindowOpen()
        async throws
    {
        let project = ProjectFixtures.project(
            text: "Close after-start cancellation"
        )
        let destination = temporaryDirectory.appendingPathComponent(
            "Close Cancelled.myshottr",
            isDirectory: true
        )
        let session = DocumentSession()
        try session.open(project: project)
        try session.markModified()
        let store = OutputProjectStoreSpy()
        let presenter = OutputErrorPresenterSpy()
        var statuses: [OutputStatusRecord] = []
        var closeCount = 0
        let controller = try DocumentWindowController(
            project: project,
            projectURL: destination,
            projectStore: store,
            errorPresenter: presenter,
            testSession: session,
            annotationSnapshotProvider: {
                throw CancellationError()
            },
            pendingChangesDecisionProvider: { .save },
            closeWindow: { closeCount += 1 },
            operationStatusSender: { requestID, status in
                statuses.append(
                    OutputStatusRecord(
                        requestID: requestID,
                        status: status
                    )
                )
            },
            commandWindowPredicate: { _ in true }
        )
        let window = try XCTUnwrap(controller.window)
        try await controller.waitForEditorLoad()

        XCTAssertFalse(controller.windowShouldClose(window))
        await waitUntil { statuses.count == 2 }

        XCTAssertEqual(
            statuses.map(\.status),
            [.started(.save), .cancelled(.save)]
        )
        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertTrue(session.isModified)
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)
    }

    func testClosePromptFailedSaveKeepsWindowOpen()
        async throws
    {
        let project = ProjectFixtures.project(
            text: "Close failed"
        )
        let destination = temporaryDirectory.appendingPathComponent(
            "Close Failed.myshottr",
            isDirectory: true
        )
        let session = DocumentSession()
        try session.open(project: project)
        try session.markModified()
        let store = OutputProjectStoreSpy()
        let presenter = OutputErrorPresenterSpy()
        var statuses: [OutputStatusRecord] = []
        var closeCount = 0
        let controller = try DocumentWindowController(
            project: project,
            projectURL: destination,
            projectStore: store,
            errorPresenter: presenter,
            testSession: session,
            annotationSnapshotProvider: {
                throw OutputTestError.saveFailure
            },
            pendingChangesDecisionProvider: { .save },
            closeWindow: { closeCount += 1 },
            operationStatusSender: { requestID, status in
                statuses.append(
                    OutputStatusRecord(
                        requestID: requestID,
                        status: status
                    )
                )
            },
            commandWindowPredicate: { _ in true }
        )
        let window = try XCTUnwrap(controller.window)
        try await controller.waitForEditorLoad()

        XCTAssertFalse(controller.windowShouldClose(window))
        await waitUntil {
            presenter.presentedViewModels.count == 1
        }

        XCTAssertEqual(
            statuses.map(\.status),
            [.started(.save), .failed(.save)]
        )
        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertTrue(session.isModified)
        XCTAssertEqual(
            presenter.presentedViewModels,
            [MyShottrUserFacingError.projectSave.viewModel]
        )
    }

    func testClosePromptSaveCannotBypassSuspendedOutputGuard()
        async throws
    {
        let project = ProjectFixtures.project(
            text: "Close guard overlap"
        )
        let destination = temporaryDirectory.appendingPathComponent(
            "Close Guard.myshottr",
            isDirectory: true
        )
        let session = DocumentSession()
        try session.open(project: project)
        try session.markModified()
        let completed = try makeCompletedTransfer()
        let store = OutputProjectStoreSpy()
        let presenter = OutputErrorPresenterSpy()
        var suspendedContinuation:
            CheckedContinuation<CompositeTransfer, any Error>?
        var decisionRequestCount = 0
        var snapshotRequestCount = 0
        var statusSendCount = 0
        var clipboardWriteCount = 0
        var hideCount = 0
        let controller = try DocumentWindowController(
            project: project,
            projectURL: destination,
            projectStore: store,
            errorPresenter: presenter,
            testSession: session,
            annotationSnapshotProvider: {
                snapshotRequestCount += 1
                return project.annotationJSON
            },
            pendingChangesDecisionProvider: {
                decisionRequestCount += 1
                return .save
            },
            compositeProvider: { _ in
                return try await withCheckedThrowingContinuation {
                    continuation in
                    suspendedContinuation = continuation
                }
            },
            clipboardWriter: { _ in
                clipboardWriteCount += 1
            },
            operationStatusSender: { _, _ in
                statusSendCount += 1
            },
            windowHider: { hideCount += 1 },
            commandWindowPredicate: { _ in true }
        )
        try await controller.waitForEditorLoad()
        XCTAssertTrue(controller.copyComposite(nil))
        await waitUntil { suspendedContinuation != nil }

        let resolved = await controller
            .resolvePendingChangesForTermination()

        XCTAssertFalse(resolved)
        XCTAssertEqual(decisionRequestCount, 1)
        XCTAssertEqual(snapshotRequestCount, 0)
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertEqual(statusSendCount, 0)
        XCTAssertEqual(clipboardWriteCount, 0)
        XCTAssertEqual(hideCount, 0)
        XCTAssertTrue(presenter.presentedViewModels.isEmpty)

        suspendedContinuation?.resume(
            returning: completed.transfer
        )
        await waitUntil { hideCount == 1 }
        XCTAssertEqual(clipboardWriteCount, 1)
    }

    private func makeController(
        project: MyShottrProject,
        session: DocumentSession,
        errorPresenter: any UserFacingErrorPresenting,
        compositeProvider:
            @escaping @MainActor (URL?) async throws
                -> CompositeTransfer,
        clipboardWriter:
            @escaping @MainActor (Data) throws -> Void,
        windowHider:
            @escaping @MainActor () -> Void,
        operationStatusSender:
            @escaping @MainActor (
                UUID,
                EditorOperationStatus
            ) -> Void = { _, _ in }
    ) throws -> DocumentWindowController {
        try DocumentWindowController(
            project: project,
            projectURL: nil,
            errorPresenter: errorPresenter,
            testSession: session,
            compositeProvider: compositeProvider,
            clipboardWriter: clipboardWriter,
            operationStatusSender: operationStatusSender,
            windowHider: windowHider,
            commandWindowPredicate: { _ in true }
        )
    }

    private func makeCompletedTransfer() throws -> (
        transfer: CompositeTransfer,
        fileURL: URL
    ) {
        let directory = try makeTransferDirectory()
        let transfer = try CompositeTransfer.begin(
            requestId: UUID(),
            expectedChunks: 1,
            directory: directory
        )
        try transfer.append(
            index: 0,
            base64: ProjectFixtures.pngData.base64EncodedString()
        )
        return (transfer, try transfer.finish())
    }

    private func makeUnfinishedTransfer() throws -> (
        transfer: CompositeTransfer,
        directory: URL
    ) {
        let directory = try makeTransferDirectory()
        let transfer = try CompositeTransfer.begin(
            requestId: UUID(),
            expectedChunks: 1,
            directory: directory
        )
        return (transfer, directory)
    }

    private func makeTransferDirectory() throws -> URL {
        let directory = temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        return directory
    }

    private func makeCopyToolbarItem(
        _ controller: DocumentWindowController
    ) throws -> NSToolbarItem {
        let toolbar = try XCTUnwrap(controller.window?.toolbar)
        return try XCTUnwrap(
            controller.toolbar(
                toolbar,
                itemForItemIdentifier: .copyComposite,
                willBeInsertedIntoToolbar: true
            )
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for async output state")
    }
}

private final class OutputProjectStoreSpy:
    ProjectPackageStoring,
    @unchecked Sendable
{
    private(set) var saveCount = 0
    private(set) var savedProjects: [MyShottrProject] = []
    private(set) var savedURLs: [URL] = []
    var onSave: ((MyShottrProject, URL) -> Void)?

    func load(from url: URL) throws -> MyShottrProject {
        throw OutputProjectStoreSpyError.unexpectedLoad
    }

    func save(
        _ project: MyShottrProject,
        to url: URL
    ) throws {
        saveCount += 1
        savedProjects.append(project)
        savedURLs.append(url)
        onSave?(project, url)
    }
}

private enum OutputProjectStoreSpyError: Error {
    case unexpectedLoad
}

private enum OutputTestError: Error {
    case saveFailure
}

private struct OutputStatusRecord: Equatable {
    let requestID: UUID
    let status: EditorOperationStatus
}

@MainActor
private final class OutputErrorPresenterSpy:
    UserFacingErrorPresenting
{
    private(set) var presentedViewModels:
        [UserFacingErrorViewModel] = []
    private let onPresent: @MainActor () -> Void

    init(onPresent: @escaping @MainActor () -> Void = {}) {
        self.onPresent = onPresent
    }

    func present(
        _ error: MyShottrUserFacingError,
        from window: NSWindow?
    ) {
        presentedViewModels.append(error.viewModel)
        onPresent()
    }
}
