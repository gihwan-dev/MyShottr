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
        XCTAssertEqual(
            exportedType["UTTypeConformsTo"] as? [String],
            ["com.apple.package"]
        )
        let tags = try XCTUnwrap(
            exportedType["UTTypeTagSpecification"] as? [String: Any]
        )
        XCTAssertEqual(
            tags["public.filename-extension"] as? [String],
            ["inkbeam"]
        )
    }

    func testSparkleSecurityKeysAreStrict() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertNil(info["SUEnableAutomaticChecks"])
        XCTAssertEqual(info["SUScheduledCheckInterval"] as? Int, 86_400)
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, false)
        XCTAssertEqual(info["SUAllowsAutomaticUpdates"] as? Bool, false)
        XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false)
        XCTAssertEqual(info["SUEnableJavaScript"] as? Bool, false)
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(info["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(
            info["SUSignedFeedFailureExpirationInterval"] as? Int,
            0
        )
        XCTAssertNotNil(info["SUPublicEDKey"] as? String)
        XCTAssertNotNil(
            URL(string: try XCTUnwrap(info["SUFeedURL"] as? String))
        )
        let channel = try XCTUnwrap(info["InkbeamReleaseChannel"] as? String)
        XCTAssertTrue(["Release Candidate", "Stable"].contains(channel))
    }
}
