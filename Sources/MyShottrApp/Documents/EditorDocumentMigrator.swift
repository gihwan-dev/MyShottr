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
            object["schemaVersion"] = 2
            object["presentation"] = ["type": "none"]
        case 2:
            break
        default:
            throw EditorDocumentMigrationError.unsupportedVersion(version)
        }

        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
