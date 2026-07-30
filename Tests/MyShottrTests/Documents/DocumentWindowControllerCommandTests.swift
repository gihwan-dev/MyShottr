import AppKit
import XCTest
@testable import MyShottr

@MainActor
final class DocumentWindowControllerCommandTests: XCTestCase {
    func testDocumentCommandsAreInstalledOnTheWindowResponderChain() throws {
        let controller = try DocumentWindowController(
            project: ProjectFixtures.project(text: "Command routing"),
            projectURL: nil
        )
        let window = try XCTUnwrap(controller.window)

        XCTAssertTrue(window.nextResponder === controller)
        XCTAssertTrue(controller.responds(to: #selector(DocumentWindowController.copyComposite(_:))))
        XCTAssertTrue(controller.responds(to: #selector(DocumentWindowController.saveProjectAction(_:))))
        XCTAssertTrue(controller.responds(to: #selector(DocumentWindowController.exportComposite(_:))))
        XCTAssertFalse(controller.copyComposite(nil))
        XCTAssertFalse(controller.saveProjectAction(nil))
        XCTAssertFalse(controller.exportComposite(nil))
    }

    func testErrorPresentationTerminatesWhenTheDocumentWindowIsUnavailable() throws {
        let presenter = SpyUserFacingErrorPresenter()
        let controller = try DocumentWindowController(
            project: ProjectFixtures.project(text: "Missing error window"),
            projectURL: nil,
            errorPresenter: presenter
        )
        controller.window = nil

        XCTAssertTrue(controller.present(.pngExport))
        XCTAssertEqual(
            presenter.presentedViewModels,
            [MyShottrUserFacingError.pngExport.viewModel]
        )
        XCTAssertEqual(presenter.windowWasProvided, [false])
    }

    func testErrorPresentationForDocumentUsesItsExistingWindowExactlyOnce()
        throws
    {
        let presenter = SpyUserFacingErrorPresenter()
        let controller = try DocumentWindowController(
            project: ProjectFixtures.project(text: "Document error"),
            projectURL: nil,
            errorPresenter: presenter
        )

        XCTAssertTrue(controller.present(.projectSave))

        XCTAssertEqual(
            presenter.presentedViewModels,
            [MyShottrUserFacingError.projectSave.viewModel]
        )
        XCTAssertEqual(presenter.windowWasProvided, [true])
    }
}

@MainActor
private final class SpyUserFacingErrorPresenter:
    UserFacingErrorPresenting
{
    private(set) var presentedViewModels:
        [UserFacingErrorViewModel] = []
    private(set) var windowWasProvided: [Bool] = []

    func present(
        _ error: MyShottrUserFacingError,
        from window: NSWindow?
    ) {
        presentedViewModels.append(error.viewModel)
        windowWasProvided.append(window != nil)
    }
}
