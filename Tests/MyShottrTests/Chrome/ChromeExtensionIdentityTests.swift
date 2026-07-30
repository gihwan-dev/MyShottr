import XCTest
@testable import MyShottr

final class ChromeExtensionIdentityTests: XCTestCase {
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
