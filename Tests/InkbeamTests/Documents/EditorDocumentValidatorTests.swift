import Foundation
import XCTest
@testable import Inkbeam

final class EditorDocumentValidatorTests: XCTestCase {
    func testAcceptsExactCurrentDocument() throws {
        let current = try ProjectFixtures.currentAnnotationJSON()

        XCTAssertNoThrow(
            try EditorDocumentValidator.validate(current)
        )
    }

    func testAcceptsIntegerDimensionsMatchingManifestExpectations()
        throws
    {
        let current = try ProjectFixtures.currentAnnotationJSON()

        XCTAssertNoThrow(
            try EditorDocumentValidator.validate(
                current,
                expectedPixelWidth: 2,
                expectedPixelHeight: 2
            )
        )
    }

    func testAcceptsPositiveFractionalDimensionsWithoutManifestExpectations()
        throws
    {
        var document = try currentDocument()
        document["sourcePixelWidth"] = 2.5
        document["sourcePixelHeight"] = 1.25

        XCTAssertNoThrow(
            try EditorDocumentValidator.validate(data(document))
        )
    }

    func testRejectsLegacyAndFutureSchemaVersions() throws {
        for document in [
            try ProjectFixtures.schemaOneAnnotationJSON(),
            try ProjectFixtures.schemaTwoAnnotationJSON(),
            try ProjectFixtures.futureAnnotationJSON(),
        ] {
            XCTAssertThrowsError(
                try EditorDocumentValidator.validate(document)
            )
        }
    }

    func testRejectsMissingAndExtraTopLevelKeys() throws {
        var missing = try currentDocument()
        missing.removeValue(forKey: "presentation")
        var extra = try currentDocument()
        extra["extra"] = true

        for document in [missing, extra] {
            XCTAssertThrowsError(
                try EditorDocumentValidator.validate(data(document))
            )
        }
    }

    func testRejectsMissingAndExtraDefaultKeys() throws {
        var missing = try currentDocument()
        var missingDefaults = try defaults(from: missing)
        missingDefaults.removeValue(forKey: "rectangleFillColor")
        missing["defaults"] = missingDefaults

        var extra = try currentDocument()
        var extraDefaults = try defaults(from: extra)
        extraDefaults["extra"] = true
        extra["defaults"] = extraDefaults

        for document in [missing, extra] {
            XCTAssertThrowsError(
                try EditorDocumentValidator.validate(data(document))
            )
        }
    }

    func testAcceptsNullAndApprovedRectangleFillDefaults() throws {
        var filled = try currentDocument()
        var filledDefaults = try defaults(from: filled)
        filledDefaults["rectangleFillColor"] = "#FADB14"
        filled["defaults"] = filledDefaults

        XCTAssertNoThrow(
            try EditorDocumentValidator.validate(
                ProjectFixtures.currentAnnotationJSON()
            )
        )
        XCTAssertNoThrow(
            try EditorDocumentValidator.validate(data(filled))
        )
    }

    func testRejectsInvalidRectangleFillDefaultTypesAndValues() throws {
        for invalidFill: Any in ["#FFFFFF", 42] {
            var document = try currentDocument()
            var documentDefaults = try defaults(from: document)
            documentDefaults["rectangleFillColor"] = invalidFill
            document["defaults"] = documentDefaults

            XCTAssertThrowsError(
                try EditorDocumentValidator.validate(data(document))
            )
        }
    }

    func testRejectsInvalidHighlighterOpacityDefaults() throws {
        for invalidOpacity: Any in [0.75, "0.5"] {
            var document = try currentDocument()
            var documentDefaults = try defaults(from: document)
            documentDefaults["highlighterOpacity"] = invalidOpacity
            document["defaults"] = documentDefaults

            XCTAssertThrowsError(
                try EditorDocumentValidator.validate(data(document))
            )
        }
    }

    func testRejectsInvalidPresentation() throws {
        for presentation: [String: Any] in [
            ["type": "slide"],
            ["type": "none", "extra": true],
        ] {
            var document = try currentDocument()
            document["presentation"] = presentation

            XCTAssertThrowsError(
                try EditorDocumentValidator.validate(data(document))
            )
        }
    }

    func testRejectsNonPositiveDimensions() throws {
        for (key, value): (String, Any) in [
            ("sourcePixelWidth", 0),
            ("sourcePixelHeight", -1),
        ] {
            var document = try currentDocument()
            document[key] = value

            XCTAssertThrowsError(
                try EditorDocumentValidator.validate(data(document))
            )
        }
    }

    func testRejectsDimensionsThatDoNotMatchManifestExpectations()
        throws
    {
        let current = try ProjectFixtures.currentAnnotationJSON()
        XCTAssertThrowsError(
            try EditorDocumentValidator.validate(
                current,
                expectedPixelWidth: 3,
                expectedPixelHeight: 2
            )
        )
        XCTAssertThrowsError(
            try EditorDocumentValidator.validate(
                current,
                expectedPixelWidth: 2,
                expectedPixelHeight: 3
            )
        )

        var fractional = try currentDocument()
        fractional["sourcePixelWidth"] = 2.5
        XCTAssertThrowsError(
            try EditorDocumentValidator.validate(
                data(fractional),
                expectedPixelWidth: 2,
                expectedPixelHeight: 2
            )
        )
    }

    func testRejectsDuplicateElementIDs() throws {
        var document = try currentDocument()
        let first = try XCTUnwrap(
            (document["elements"] as? [[String: Any]])?.first
        )
        var second = first
        second["zIndex"] = 1
        document["elements"] = [first, second]

        XCTAssertThrowsError(
            try EditorDocumentValidator.validate(data(document))
        )
    }

    func testRejectsDuplicateElementZIndices() throws {
        var document = try currentDocument()
        let first = try XCTUnwrap(
            (document["elements"] as? [[String: Any]])?.first
        )
        var second = first
        second["id"] = "text-2"
        document["elements"] = [first, second]

        XCTAssertThrowsError(
            try EditorDocumentValidator.validate(data(document))
        )
    }

    func testRejectsEmptyElementID() throws {
        var document = try currentDocument()
        var element = try firstElement(from: document)
        element["id"] = ""
        document["elements"] = [element]

        XCTAssertThrowsError(
            try EditorDocumentValidator.validate(data(document))
        )
    }

    func testRejectsMissingAndExtraElementKeys() throws {
        var missing = try currentDocument()
        var missingElement = try firstElement(from: missing)
        missingElement.removeValue(forKey: "text")
        missing["elements"] = [missingElement]

        var extra = try currentDocument()
        var extraElement = try firstElement(from: extra)
        extraElement["extra"] = true
        extra["elements"] = [extraElement]

        for document in [missing, extra] {
            XCTAssertThrowsError(
                try EditorDocumentValidator.validate(data(document))
            )
        }
    }

    func testRejectsUnsupportedElementType() throws {
        var document = try currentDocument()
        var element = try firstElement(from: document)
        element["type"] = "video"
        document["elements"] = [element]

        XCTAssertThrowsError(
            try EditorDocumentValidator.validate(data(document))
        )
    }

    func testRejectsNonFiniteNumericValues() throws {
        let current = try ProjectFixtures.currentAnnotationJSON()
        let json = try XCTUnwrap(
            String(data: current, encoding: .utf8)
        )
        let nonFinite = Data(
            json.replacingOccurrences(
                of: "\"x\":0",
                with: "\"x\":1e400"
            ).utf8
        )

        XCTAssertThrowsError(
            try EditorDocumentValidator.validate(nonFinite)
        )
    }

    func testAcceptsEverySupportedElementShape() throws {
        var document = try currentDocument()
        document["elements"] = supportedElements()

        XCTAssertNoThrow(
            try EditorDocumentValidator.validate(data(document))
        )
    }

    private func currentDocument() throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: ProjectFixtures.currentAnnotationJSON()
            ) as? [String: Any]
        )
    }

    private func defaults(
        from document: [String: Any]
    ) throws -> [String: Any] {
        try XCTUnwrap(document["defaults"] as? [String: Any])
    }

    private func firstElement(
        from document: [String: Any]
    ) throws -> [String: Any] {
        try XCTUnwrap(
            (document["elements"] as? [[String: Any]])?.first
        )
    }

    private func data(_ document: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: document,
            options: [.sortedKeys]
        )
    }

    private func supportedElements() -> [[String: Any]] {
        let base: (String, String, Int) -> [String: Any] = {
            id, type, zIndex in
            [
                "id": id,
                "type": type,
                "x": 0,
                "y": 0,
                "width": 10,
                "height": 10,
                "rotation": 0,
                "opacity": 1,
                "zIndex": zIndex,
                "seed": zIndex + 1,
            ]
        }
        var rectangle = base("rectangle-1", "rectangle", 0)
        rectangle.merge([
            "strokeColor": "#1677FF",
            "strokeWidth": 4,
            "fillColor": NSNull(),
            "roughness": 1,
        ]) { _, new in new }
        var arrow = base("arrow-1", "arrow", 1)
        arrow.merge([
            "points": [["x": 0, "y": 0], ["x": 10, "y": 10]],
            "strokeColor": "#FF4D4F",
            "strokeWidth": 2,
            "roughness": 2,
        ]) { _, new in new }
        var line = base("line-1", "line", 2)
        line.merge([
            "points": [["x": 0, "y": 0], ["x": 10, "y": 10]],
            "strokeColor": "#000000",
            "strokeWidth": 8,
            "roughness": 0,
        ]) { _, new in new }
        var text = base("text-1", "text", 3)
        text.merge([
            "text": "Text",
            "color": "#1677FF",
            "fontSize": 24,
        ]) { _, new in new }
        var freehand = base("freehand-1", "freehand", 4)
        freehand.merge([
            "points": [["x": 0, "y": 0]],
            "color": "#FADB14",
            "strokeWidth": 4,
        ]) { _, new in new }
        var highlighter = base(
            "highlighter-1",
            "highlighter",
            5
        )
        highlighter.merge([
            "points": [["x": 0, "y": 0]],
            "color": "#FADB14",
            "strokeWidth": 8,
            "opacity": 0.5,
        ]) { _, new in new }
        var blur = base("blur-1", "blur", 6)
        blur["radius"] = 12
        var redaction = base("redaction-1", "redaction", 7)
        redaction["color"] = "#000000"
        var marker = base("marker-1", "numberMarker", 8)
        marker.merge([
            "number": 1,
            "color": "#FF4D4F",
        ]) { _, new in new }

        return [
            rectangle,
            arrow,
            line,
            text,
            freehand,
            highlighter,
            blur,
            redaction,
            marker,
        ]
    }
}
