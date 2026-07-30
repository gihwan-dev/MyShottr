import Foundation
import XCTest
@testable import MyShottr

@MainActor
final class RegionCaptureCoordinatorTests: XCTestCase {
    private let artifactID = UUID(
        uuidString: "299BEFAA-FF18-49FD-B39B-58F622AF1605"
    )!
    private let captureDate = Date(timeIntervalSince1970: 1_722_222_222)

    func testConfirmedSelectionOpensScreenRegionDocument() async throws {
        let selector = FakeRegionSelector(
            result: .confirmed(CaptureFixtures.selection)
        )
        let recorder = CaptureInvocationRecorder()
        let capturer = FakeScreenCapturer(
            result: try artifact(),
            recorder: recorder
        )
        let windows = SpyDocumentWindowPresenter()
        let coordinator = RegionCaptureCoordinator(
            selector: selector,
            capturer: capturer,
            projectFactory: StubNewProjectFactory(),
            windows: windows,
            now: { self.captureDate }
        )

        let error = await coordinator.captureArea()
        let capturedSelections = await recorder.selections

        XCTAssertNil(error)
        XCTAssertEqual(selector.selectionCount, 1)
        XCTAssertEqual(capturedSelections, [CaptureFixtures.selection])
        XCTAssertEqual(windows.presentedProjects.count, 1)
        let project = try XCTUnwrap(windows.presentedProjects.first)
        XCTAssertEqual(project.manifest.documentId, artifactID)
        XCTAssertEqual(project.manifest.createdAt, captureDate)
        XCTAssertEqual(project.manifest.updatedAt, captureDate)
        XCTAssertEqual(project.manifest.sourceKind, .screenRegion)
        XCTAssertEqual(project.originalPNG, ProjectFixtures.pngData)
    }

    func testCancelledSelectionDoesNotCaptureOrOpenWindow() async throws {
        let selector = FakeRegionSelector(result: .cancelled)
        let recorder = CaptureInvocationRecorder()
        let windows = SpyDocumentWindowPresenter()
        let coordinator = RegionCaptureCoordinator(
            selector: selector,
            capturer: FakeScreenCapturer(
                result: try artifact(),
                recorder: recorder
            ),
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        let error = await coordinator.captureArea()
        let capturedSelections = await recorder.selections

        XCTAssertNil(error)
        XCTAssertTrue(capturedSelections.isEmpty)
        XCTAssertTrue(windows.presentedProjects.isEmpty)
    }

    func testSecondTriggerReturnsAlreadyInProgressWithoutStartingAnotherSelection() async throws {
        let selector = SuspendingRegionSelector()
        let windows = SpyDocumentWindowPresenter()
        let coordinator = RegionCaptureCoordinator(
            selector: selector,
            capturer: FakeScreenCapturer(result: try artifact()),
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )
        let firstCapture = Task {
            await coordinator.captureArea()
        }
        await selector.waitUntilStarted()

        let secondError = await coordinator.captureArea()

        if case .capture(.captureAlreadyInProgress)? = secondError {
            // Expected typed duplicate-trigger result.
        } else {
            XCTFail("Expected captureAlreadyInProgress")
        }
        XCTAssertEqual(selector.selectionCount, 1)
        XCTAssertTrue(windows.presentedProjects.isEmpty)

        selector.finish(with: .cancelled)
        let firstError = await firstCapture.value
        XCTAssertNil(firstError)
    }

    func testSelectionFailureDoesNotCaptureOrOpenWindow() async throws {
        let selector = ThrowingRegionSelector()
        let recorder = CaptureInvocationRecorder()
        let windows = SpyDocumentWindowPresenter()
        let coordinator = RegionCaptureCoordinator(
            selector: selector,
            capturer: FakeScreenCapturer(
                result: try artifact(),
                recorder: recorder
            ),
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        let error = await coordinator.captureArea()
        let capturedSelections = await recorder.selections

        XCTAssertEqual(
            error?.viewModel.title,
            "Screen Capture Failed"
        )
        XCTAssertTrue(capturedSelections.isEmpty)
        XCTAssertTrue(windows.presentedProjects.isEmpty)
    }

    func testCaptureFailureDoesNotCreateProjectOrOpenWindow() async {
        let recorder = CaptureInvocationRecorder()
        let windows = SpyDocumentWindowPresenter()
        let coordinator = RegionCaptureCoordinator(
            selector: FakeRegionSelector(
                result: .confirmed(CaptureFixtures.selection)
            ),
            capturer: ThrowingScreenCapturer(
                error: .capture,
                recorder: recorder
            ),
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        let error = await coordinator.captureArea()
        let capturedSelections = await recorder.selections

        XCTAssertEqual(
            error?.viewModel.title,
            "Screen Capture Failed"
        )
        XCTAssertEqual(capturedSelections, [CaptureFixtures.selection])
        XCTAssertTrue(windows.presentedProjects.isEmpty)
    }

    func testProjectCreationFailureDoesNotOpenWindow() async throws {
        let windows = SpyDocumentWindowPresenter()
        let coordinator = RegionCaptureCoordinator(
            selector: FakeRegionSelector(
                result: .confirmed(CaptureFixtures.selection)
            ),
            capturer: FakeScreenCapturer(result: try artifact()),
            projectFactory: ThrowingNewProjectFactory(
                error: .projectCreation
            ),
            windows: windows
        )

        let error = await coordinator.captureArea()

        XCTAssertEqual(
            error?.viewModel.title,
            "Screen Capture Failed"
        )
        XCTAssertTrue(windows.presentedProjects.isEmpty)
    }

    func testWindowPresentationFailureIsReturned() async throws {
        let windows = SpyDocumentWindowPresenter()
        windows.presentationError = CapturePipelineTestError.presentation
        let coordinator = RegionCaptureCoordinator(
            selector: FakeRegionSelector(
                result: .confirmed(CaptureFixtures.selection)
            ),
            capturer: FakeScreenCapturer(result: try artifact()),
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        let error = await coordinator.captureArea()

        XCTAssertEqual(
            error?.viewModel.title,
            "Screen Capture Failed"
        )
        XCTAssertTrue(windows.presentedProjects.isEmpty)
    }

    private func artifact() throws -> CaptureArtifact {
        try CaptureArtifact(
            id: artifactID,
            sourceKind: .screenRegion,
            pngData: ProjectFixtures.pngData,
            scale: 2
        )
    }
}
