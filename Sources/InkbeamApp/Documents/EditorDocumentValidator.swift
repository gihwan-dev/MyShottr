import Foundation

enum EditorDocumentValidationError: Error, Equatable {
    case invalidDocument
}

enum EditorDocumentValidator {
    private static let topLevelKeys: Set<String> = [
        "schemaVersion",
        "sourcePixelWidth",
        "sourcePixelHeight",
        "elements",
        "presentation",
        "defaults",
    ]
    private static let defaultKeys: Set<String> = [
        "color",
        "strokeWidth",
        "textSize",
        "roughness",
        "opacity",
        "rectangleFillColor",
        "highlighterOpacity",
    ]
    private static let supportedElementTypes: Set<String> = [
        "rectangle",
        "arrow",
        "line",
        "text",
        "freehand",
        "highlighter",
        "blur",
        "redaction",
        "numberMarker",
    ]
    private static let colors: Set<String> = [
        "#000000",
        "#FF4D4F",
        "#1677FF",
        "#FADB14",
    ]
    private static let opacities: Set<Double> = [
        0.25,
        0.5,
        0.75,
        1,
    ]

    static func validate(
        _ data: Data,
        expectedPixelWidth: Int? = nil,
        expectedPixelHeight: Int? = nil
    ) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw EditorDocumentValidationError.invalidDocument
        }

        guard
            let document = object as? [String: Any],
            Set(document.keys) == topLevelKeys,
            integer(document["schemaVersion"]) == 3,
            let sourcePixelWidth = number(
                document["sourcePixelWidth"]
            ),
            sourcePixelWidth > 0,
            let sourcePixelHeight = number(
                document["sourcePixelHeight"]
            ),
            sourcePixelHeight > 0,
            expectedPixelWidth.map({
                Double($0) == sourcePixelWidth
            }) ?? true,
            expectedPixelHeight.map({
                Double($0) == sourcePixelHeight
            })
                ?? true,
            let elements = document["elements"] as? [[String: Any]],
            let presentation = document["presentation"]
                as? [String: Any],
            Set(presentation.keys) == ["type"],
            presentation["type"] as? String == "none",
            let defaults = document["defaults"] as? [String: Any],
            validateDefaults(defaults)
        else {
            throw EditorDocumentValidationError.invalidDocument
        }

        var ids = Set<String>()
        var zIndices = Set<Double>()
        guard elements.allSatisfy({ element in
            guard
                let id = element["id"] as? String,
                !id.isEmpty,
                let zIndex = number(element["zIndex"]),
                ids.insert(id).inserted,
                zIndices.insert(zIndex).inserted
            else {
                return false
            }
            return validateElement(element)
        }) else {
            throw EditorDocumentValidationError.invalidDocument
        }
    }

    private static func validateDefaults(
        _ defaults: [String: Any]
    ) -> Bool {
        Set(defaults.keys) == defaultKeys
            && colors.contains(defaults["color"] as? String ?? "")
            && [2, 4, 8].contains(
                integer(defaults["strokeWidth"]) ?? -1
            )
            && [16, 24, 36].contains(
                integer(defaults["textSize"]) ?? -1
            )
            && [0, 1, 2].contains(
                integer(defaults["roughness"]) ?? -1
            )
            && opacities.contains(
                number(defaults["opacity"]) ?? -1
            )
            && (
                defaults["rectangleFillColor"] is NSNull
                    || colors.contains(
                        defaults["rectangleFillColor"]
                            as? String ?? ""
                    )
            )
            && [0.25, 0.5].contains(
                number(defaults["highlighterOpacity"]) ?? -1
            )
    }

    private static func validateElement(
        _ element: [String: Any]
    ) -> Bool {
        guard
            let type = element["type"] as? String,
            supportedElementTypes.contains(type),
            let id = element["id"] as? String,
            !id.isEmpty,
            ["x", "y", "rotation", "zIndex", "seed"]
                .allSatisfy({ finite(element[$0]) }),
            let width = number(element["width"]),
            width >= 0,
            let height = number(element["height"]),
            height >= 0,
            let opacity = number(element["opacity"]),
            opacities.contains(opacity)
        else {
            return false
        }

        let base: Set<String> = [
            "id",
            "type",
            "x",
            "y",
            "width",
            "height",
            "rotation",
            "opacity",
            "zIndex",
            "seed",
        ]
        switch type {
        case "rectangle":
            return Set(element.keys) == base.union([
                "strokeColor",
                "strokeWidth",
                "fillColor",
                "roughness",
            ])
                && style(element)
                && (
                    element["fillColor"] is NSNull
                        || colors.contains(
                            element["fillColor"] as? String ?? ""
                        )
                )
        case "arrow", "line":
            return Set(element.keys) == base.union([
                "points",
                "strokeColor",
                "strokeWidth",
                "roughness",
            ])
                && style(element)
                && points(element["points"], count: 2)
        case "text":
            return Set(element.keys) == base.union([
                "text",
                "color",
                "fontSize",
            ])
                && element["text"] is String
                && colors.contains(
                    element["color"] as? String ?? ""
                )
                && [16, 24, 36].contains(
                    integer(element["fontSize"]) ?? -1
                )
        case "freehand":
            return Set(element.keys) == base.union([
                "points",
                "color",
                "strokeWidth",
            ])
                && points(element["points"], minimum: 1)
                && colors.contains(
                    element["color"] as? String ?? ""
                )
                && [2, 4, 8].contains(
                    integer(element["strokeWidth"]) ?? -1
                )
        case "highlighter":
            return Set(element.keys) == base.union([
                "points",
                "color",
                "strokeWidth",
            ])
                && points(element["points"], minimum: 1)
                && colors.contains(
                    element["color"] as? String ?? ""
                )
                && integer(element["strokeWidth"]) == 8
                && [0.25, 0.5].contains(
                    number(element["opacity"]) ?? -1
                )
        case "blur":
            return Set(element.keys) == base.union(["radius"])
                && integer(element["radius"]) == 12
                && number(element["opacity"]) == 1
                && number(element["rotation"]) == 0
        case "redaction":
            return Set(element.keys) == base.union(["color"])
                && element["color"] as? String == "#000000"
                && number(element["opacity"]) == 1
        case "numberMarker":
            return Set(element.keys) == base.union([
                "number",
                "color",
            ])
                && finite(element["number"])
                && colors.contains(
                    element["color"] as? String ?? ""
                )
        default:
            return false
        }
    }

    private static func style(_ element: [String: Any]) -> Bool {
        colors.contains(element["strokeColor"] as? String ?? "")
            && [2, 4, 8].contains(
                integer(element["strokeWidth"]) ?? -1
            )
            && [0, 1, 2].contains(
                integer(element["roughness"]) ?? -1
            )
    }

    private static func points(
        _ value: Any?,
        count: Int? = nil,
        minimum: Int = 0
    ) -> Bool {
        guard
            let points = value as? [[String: Any]],
            points.count >= minimum,
            count == nil || points.count == count
        else {
            return false
        }
        return points.allSatisfy {
            Set($0.keys) == ["x", "y"]
                && finite($0["x"])
                && finite($0["y"])
        }
    }

    private static func finite(_ value: Any?) -> Bool {
        number(value) != nil
    }

    private static func number(_ value: Any?) -> Double? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite
        else {
            return nil
        }
        return number.doubleValue
    }

    private static func integer(_ value: Any?) -> Int? {
        guard
            let number = number(value),
            number.rounded() == number,
            number >= Double(Int.min),
            number <= Double(Int.max)
        else {
            return nil
        }
        return Int(number)
    }
}
