import XCTest
@testable import Inkbeam

@MainActor
final class DocumentSessionTests: XCTestCase {
    func testUnsavedCaptureStartsModifiedWithoutChangingItsContent()
        throws
    {
        let project = ProjectFixtures.project(text: "capture")
        let session = DocumentSession()

        try session.openUnsaved(project: project)

        XCTAssertEqual(session.project, project)
        XCTAssertTrue(session.isModified)
        XCTAssertEqual(session.modificationRevision, 1)
    }

    func testEveryEditorChangeAdvancesTheModificationRevision()
        throws
    {
        let session = DocumentSession()
        try session.open(
            project: ProjectFixtures.project(text: "initial")
        )

        try session.markModified()
        try session.markModified()

        XCTAssertTrue(session.isModified)
        XCTAssertEqual(session.modificationRevision, 2)
    }

    func testSaveDoesNotClearChangesMadeDuringTheSave() throws {
        let initial = ProjectFixtures.project(text: "initial")
        let saved = ProjectFixtures.project(text: "saved")
        let session = DocumentSession()
        try session.open(project: initial)
        try session.applySnapshot(saved.annotationJSON)
        let revisionAtSaveStart = session.modificationRevision
        try session.markModified()

        let completion = try session.completeSave(
            saved,
            expectedModificationRevision: revisionAtSaveStart
        )

        guard case .savedWithNewerChanges = completion else {
            return XCTFail("Expected newer editor changes to remain modified")
        }
        XCTAssertTrue(session.isModified)
    }

    func testOpenRejectsLegacySchemaAsInvalidDocument() throws {
        var project = ProjectFixtures.project(text: "legacy")
        project.annotationJSON = try ProjectFixtures
            .schemaTwoAnnotationJSON()
        let session = DocumentSession()

        XCTAssertThrowsError(try session.open(project: project)) {
            XCTAssertEqual(
                $0 as? DocumentSessionError,
                .invalidDocument
            )
        }
        XCTAssertFalse(session.isOpen)
    }
}
