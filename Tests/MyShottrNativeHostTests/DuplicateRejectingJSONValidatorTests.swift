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

    func testAcceptsDocumentAtConservativeNestingDepth() {
        XCTAssertTrue(
            DuplicateRejectingJSONValidator.isValid(
                deeplyNestedArray(depth: 64)
            )
        )
    }

    func testRejectsDocumentBeyondNestingDepthLimit() {
        XCTAssertFalse(
            DuplicateRejectingJSONValidator.isValid(
                deeplyNestedArray(depth: 256)
            )
        )
    }

    private func deeplyNestedArray(depth: Int) -> Data {
        Data(
            (
                String(repeating: "[", count: depth)
                    + "0"
                    + String(repeating: "]", count: depth)
            ).utf8
        )
    }
}
