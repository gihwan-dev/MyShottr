import Foundation

enum NativeToEditorMessageType: String, Codable, Sendable {
    case loadDocument, saveCompleted, saveFailed, requestComposite, setAppearance
}

enum EditorToNativeMessageType: String, Codable, Sendable {
    case editorReady, documentChanged, annotationSnapshot
    case compositeChunk, compositeCompleted, bridgeError
}

enum EditorBridgeEnvelopeError: Error, Equatable {
    case unsupportedProtocolVersion(Int)
    case payloadTooLarge
}

struct EditorBridgeEnvelope<MessageType: RawRepresentable & Codable & Sendable, Payload: Codable & Sendable>: Codable, Sendable where MessageType.RawValue == String {
    static var protocolVersion: Int { 1 }
    static var maxPayloadBytes: Int { 8 * 1024 * 1024 }

    let protocolVersion: Int
    let requestId: UUID
    let type: MessageType
    let payload: Payload

    private enum CodingKeys: String, CodingKey {
        case protocolVersion, requestId, type, payload
    }

    init(requestId: UUID = UUID(), type: MessageType, payload: Payload) throws {
        self.protocolVersion = Self.protocolVersion
        self.requestId = requestId
        self.type = type
        self.payload = payload
        try validatePayloadSize()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        guard protocolVersion == Self.protocolVersion else {
            throw EditorBridgeEnvelopeError.unsupportedProtocolVersion(protocolVersion)
        }
        self.protocolVersion = protocolVersion
        self.requestId = try container.decode(UUID.self, forKey: .requestId)
        self.type = try container.decode(MessageType.self, forKey: .type)
        self.payload = try container.decode(Payload.self, forKey: .payload)
        try validatePayloadSize()
    }

    func encode(to encoder: Encoder) throws {
        try validatePayloadSize()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(type, forKey: .type)
        try container.encode(payload, forKey: .payload)
    }

    private func validatePayloadSize() throws {
        guard try JSONEncoder().encode(payload).count <= Self.maxPayloadBytes else {
            throw EditorBridgeEnvelopeError.payloadTooLarge
        }
    }
}

extension EditorBridgeEnvelope where Payload == BridgeJSONValue {
    static func decode(from data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }

    func encodedData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

typealias NativeToEditorEnvelope = EditorBridgeEnvelope<NativeToEditorMessageType, BridgeJSONValue>
typealias EditorToNativeEnvelope = EditorBridgeEnvelope<EditorToNativeMessageType, BridgeJSONValue>
