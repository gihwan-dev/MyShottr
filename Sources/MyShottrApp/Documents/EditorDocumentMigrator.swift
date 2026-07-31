import Foundation

enum EditorDocumentMigrationError: Error, Equatable {
    case malformedDocument
    case unsupportedVersion(Int)
}

enum EditorDocumentMigrator {
    static func migrate(_ data: Data) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["schemaVersion"] as? Int
        else {
            throw EditorDocumentMigrationError.malformedDocument
        }

        switch version {
        case 1:
            object["presentation"] = ["type": "none"]
            fallthrough
        case 2:
            guard var defaults = object["defaults"] as? [String: Any] else {
                throw EditorDocumentMigrationError.malformedDocument
            }
            defaults["rectangleFillColor"] = NSNull()
            defaults["highlighterOpacity"] = 0.5
            object["defaults"] = defaults
            object["schemaVersion"] = 3
        case 3:
            return data
        default:
            throw EditorDocumentMigrationError.unsupportedVersion(version)
        }

        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
