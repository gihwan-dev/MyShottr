import XCTest
import UniformTypeIdentifiers
@testable import Inkbeam

final class AppInfoPlistTests: XCTestCase {
    @MainActor
    func testOpenPanelAllowsOnlyInkbeamProjects() {
        XCTAssertEqual(
            AppDelegate.editableProjectExtension,
            "inkbeam"
        )
        XCTAssertEqual(
            UTType.inkbeamProject.identifier,
            "dev.gihwan.inkbeam.project"
        )
        XCTAssertTrue(UTType.inkbeamProject.conforms(to: .package))
    }

    func testBuiltAppProhibitsMultipleInstances() {
        XCTAssertEqual(
            Bundle.main.object(
                forInfoDictionaryKey: "LSMultipleInstancesProhibited"
            ) as? Bool,
            true
        )
    }

    func testBuiltAppDeclaresOnlyInkbeamProjectType() throws {
        let documentTypes = try XCTUnwrap(
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleDocumentTypes"
            ) as? [[String: Any]]
        )
        XCTAssertEqual(documentTypes.count, 1)
        let documentType = try XCTUnwrap(documentTypes.first)
        XCTAssertEqual(
            documentType["CFBundleTypeExtensions"] as? [String],
            ["inkbeam"]
        )
        XCTAssertEqual(
            documentType["LSItemContentTypes"] as? [String],
            ["dev.gihwan.inkbeam.project"]
        )

        let exportedTypes = try XCTUnwrap(
            Bundle.main.object(
                forInfoDictionaryKey: "UTExportedTypeDeclarations"
            ) as? [[String: Any]]
        )
        XCTAssertEqual(exportedTypes.count, 1)
        let exportedType = try XCTUnwrap(exportedTypes.first)
        XCTAssertEqual(
            exportedType["UTTypeIdentifier"] as? String,
            "dev.gihwan.inkbeam.project"
        )
        let tags = try XCTUnwrap(
            exportedType["UTTypeTagSpecification"] as? [String: Any]
        )
        XCTAssertEqual(
            tags["public.filename-extension"] as? [String],
            ["inkbeam"]
        )
    }
}
