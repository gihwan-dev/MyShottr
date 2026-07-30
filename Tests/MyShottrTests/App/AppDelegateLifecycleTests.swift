import AppKit
import Carbon
import XCTest
@testable import MyShottr

@MainActor
final class AppDelegateLifecycleTests: XCTestCase {
    func testColdFileOpenBeforeDidFinishKeepsDocumentAndRegularPolicy() {
        let project = ProjectFixtures.project(text: "Cold Open")
        let projectURL = URL(
            fileURLWithPath: "/tmp/cold-open.myshottr"
        )
        let application = SpyApplicationLifecycle()
        let window = SpyEditorWindowController()
        let delegate = AppDelegate(
            dependencies: AppDependencies(
                projectStore: StubProjectStore(project: project)
            ),
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: { openedProject, openedURL in
                XCTAssertEqual(openedProject, project)
                XCTAssertEqual(openedURL, projectURL)
                return window
            },
            hotKeyAPI: makeNoOpHotKeyAPI()
        )

        delegate.application(NSApplication.shared, open: [projectURL])
        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )

        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(application.activationPolicies, [.regular])
        XCTAssertEqual(application.activationCount, 1)
        XCTAssertEqual(window.presentationCount, 1)
    }

    func testMenuBarColdLaunchUsesAccessoryPolicy() {
        let application = SpyApplicationLifecycle()
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            hotKeyAPI: makeNoOpHotKeyAPI()
        )

        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )

        XCTAssertEqual(delegate.activeDocumentWindowCount, 0)
        XCTAssertEqual(application.activationPolicies, [.accessory])
        XCTAssertEqual(application.activationCount, 0)
    }

    func testPresentingDocumentRetainsWindowAndActivatesRegularApp() {
        let application = SpyApplicationLifecycle()
        let window = SpyEditorWindowController()
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: { _, _ in window }
        )

        delegate.present(project: ProjectFixtures.project(text: "Capture"))

        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(application.activationPolicies, [.regular])
        XCTAssertEqual(application.activationCount, 1)
        XCTAssertEqual(window.presentationCount, 1)
    }

    func testClosingLastDocumentReturnsToAccessoryPolicy() {
        let application = SpyApplicationLifecycle()
        let firstWindow = SpyEditorWindowController()
        let secondWindow = SpyEditorWindowController()
        var windows: [SpyEditorWindowController] = [
            firstWindow,
            secondWindow,
        ]
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: { _, _ in windows.removeFirst() }
        )
        delegate.present(project: ProjectFixtures.project(text: "First"))
        delegate.present(project: ProjectFixtures.project(text: "Second"))

        firstWindow.close()

        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(
            application.activationPolicies,
            [.regular, .regular]
        )

        secondWindow.close()

        XCTAssertEqual(delegate.activeDocumentWindowCount, 0)
        XCTAssertEqual(
            application.activationPolicies,
            [.regular, .regular, .accessory]
        )
    }
}

private struct StubProjectStore: ProjectPackageStoring {
    let project: MyShottrProject

    func load(from url: URL) throws -> MyShottrProject {
        project
    }

    func save(_ project: MyShottrProject, to url: URL) throws {
        throw StubProjectStoreError.unexpectedSave
    }
}

private enum StubProjectStoreError: Error {
    case unexpectedSave
}

private func makeNoOpHotKeyAPI() -> GlobalHotKeyAPI {
    GlobalHotKeyAPI(
        installEventHandler: { _, _, outputHandler in
            outputHandler.pointee = nil
            return noErr
        },
        registerEventHotKey: { _, _, _, outputHotKey in
            outputHotKey.pointee = nil
            return noErr
        },
        unregisterEventHotKey: { _ in noErr },
        removeEventHandler: { _ in noErr }
    )
}

@MainActor
private final class SpyEditorWindowController: EditorWindowControlling {
    var onClose: (() -> Void)?
    private(set) var presentationCount = 0

    func presentWindow() {
        presentationCount += 1
    }

    func close() {
        onClose?()
    }
}

@MainActor
private final class SpyApplicationLifecycle {
    private(set) var activationPolicies: [
        NSApplication.ActivationPolicy
    ] = []
    private(set) var activationCount = 0

    lazy var lifecycle = ApplicationLifecycle(
        setActivationPolicy: { [weak self] policy in
            self?.activationPolicies.append(policy)
        },
        activate: { [weak self] in
            self?.activationCount += 1
        }
    )
}
