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
    case malformedMessage
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

extension EditorBridgeEnvelope where MessageType == EditorToNativeMessageType, Payload == BridgeJSONValue {
    static func decode(from data: Data) throws -> Self {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["protocolVersion", "requestId", "type", "payload"]
        else {
            throw EditorBridgeEnvelopeError.malformedMessage
        }
        let envelope = try JSONDecoder().decode(Self.self, from: data)
        try envelope.validatePayload()
        return envelope
    }

    private func validatePayload() throws {
        guard case let .object(payload) = payload else { throw EditorBridgeEnvelopeError.malformedMessage }
        let exact: (Set<String>) -> Bool = { Set(payload.keys) == $0 }
        switch type {
        case .editorReady, .documentChanged:
            guard exact([]) else { throw EditorBridgeEnvelopeError.malformedMessage }
        case .annotationSnapshot:
            guard exact(["document"]), case let .object(document)? = payload["document"],
                  Set(document.keys) == ["schemaVersion", "sourcePixelWidth", "sourcePixelHeight", "elements", "presentation", "defaults"],
                  integer(document["schemaVersion"]) == 2,
                  case let .object(presentation)? = document["presentation"],
                  Set(presentation.keys) == ["type"],
                  case let .string(presentationType)? = presentation["type"], presentationType == "none"
            else { throw EditorBridgeEnvelopeError.malformedMessage }
        case .compositeChunk:
            guard exact(["requestId", "index", "total", "dataBase64"]),
                  uuid(payload["requestId"]), let index = integer(payload["index"]), index >= 0,
                  let total = integer(payload["total"]), total > index,
                  case .string = payload["dataBase64"]
            else { throw EditorBridgeEnvelopeError.malformedMessage }
        case .compositeCompleted:
            guard exact(["requestId"]), uuid(payload["requestId"]) else { throw EditorBridgeEnvelopeError.malformedMessage }
        case .bridgeError:
            guard exact(["code", "message"]), case let .string(code)? = payload["code"],
                  ["INVALID_DOCUMENT", "INVALID_MESSAGE", "RENDER_FAILED"].contains(code),
                  case let .string(message)? = payload["message"], !message.isEmpty
            else { throw EditorBridgeEnvelopeError.malformedMessage }
        }
    }

    private func uuid(_ value: BridgeJSONValue?) -> Bool {
        guard case let .string(string)? = value else { return false }
        return UUID(uuidString: string) != nil
    }

    private func integer(_ value: BridgeJSONValue?) -> Int? {
        guard case let .number(number)? = value, number.isFinite, number.rounded() == number else { return nil }
        return Int(exactly: number)
    }
}

typealias NativeToEditorEnvelope = EditorBridgeEnvelope<NativeToEditorMessageType, BridgeJSONValue>
typealias EditorToNativeEnvelope = EditorBridgeEnvelope<EditorToNativeMessageType, BridgeJSONValue>
