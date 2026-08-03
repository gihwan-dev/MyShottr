import XCTest
@testable import Inkbeam

final class ChromeExtensionIdentityTests: XCTestCase {
    func testAppBundledPublicKeyMatchesCommittedKeyCopiedIntoTestBundle() throws {
        let appBundledURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "chrome-extension-key",
                withExtension: "b64"
            )
        )
        let testBundledURL = try XCTUnwrap(
            Bundle(for: ChromeExtensionIdentityTests.self).url(
                forResource: "chrome-extension-key",
                withExtension: "b64"
            )
        )

        XCTAssertEqual(
            try Data(contentsOf: appBundledURL),
            try Data(contentsOf: testBundledURL)
        )
    }

    func testCommittedPublicKeyProducesKnownExtensionID() throws {
        XCTAssertEqual(
            try ChromeExtensionIdentity.id(
                fromBase64DER: ChromeFixtures.extensionPublicKeyBase64
            ),
            ChromeFixtures.extensionID
        )
    }

    func testExtensionIDHasThirtyTwoLowercaseAPCharacters() throws {
        let id = try ChromeExtensionIdentity.id(
            fromBase64DER: ChromeFixtures.extensionPublicKeyBase64
        )

        XCTAssertNotNil(
            id.range(
                of: #"^[a-p]{32}$"#,
                options: .regularExpression
            )
        )
    }

    func testInvalidBase64IsRejected() {
        XCTAssertThrowsError(
            try ChromeExtensionIdentity.id(fromBase64DER: "not/base64%%%")
        )
    }
}
