import Foundation
import XCTest

final class DuplicateRejectingJSONValidatorTests: XCTestCase {
    func testRejectsDuplicateMemberInNestedObject() {
        XCTAssertFalse(
            DuplicateRejectingJSONValidator.isValid(
                Data(#"{"outer":{"value":1,"value":2}}"#.utf8)
            )
        )
    }

    func testTreatsEscapedAndLiteralMemberNamesAsDuplicates() {
        XCTAssertFalse(
            DuplicateRejectingJSONValidator.isValid(
                Data(#"{"value":1,"\u0076alue":2}"#.utf8)
            )
        )
    }

    func testAcceptsUniqueMembersAtDifferentObjectLevels() {
        XCTAssertTrue(
            DuplicateRejectingJSONValidator.isValid(
                Data(#"{"value":1,"nested":{"value":2}}"#.utf8)
            )
        )
    }
}
