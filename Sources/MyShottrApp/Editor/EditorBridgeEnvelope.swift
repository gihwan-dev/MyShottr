import Foundation

enum NativeToEditorMessageType: String, Codable, Sendable {
    case loadDocument, saveCompleted, saveFailed, requestComposite, setAppearance
    case performHistoryAction, operationStatus
}

enum EditorToNativeMessageType: String, Codable, Sendable {
    case editorReady, documentChanged, editorPreferencesChanged, annotationSnapshot
    case compositeChunk, compositeCompleted, bridgeError, historyStateChanged
}

struct EditorHistoryState: Equatable, Sendable {
    let canUndo: Bool
    let canRedo: Bool
}

enum EditorHistoryAction: String, Equatable, Sendable {
    case undo
    case redo
}

enum EditorOutputOperation: String, Equatable, Sendable {
    case save
    case export
}

enum EditorOperationStatus: Equatable, Sendable {
    case started(EditorOutputOperation)
    case saveCompleted
    case saveSuperseded
    case exportCompleted(displayName: String)
    case cancelled(EditorOutputOperation)
    case failed(EditorOutputOperation)
}

private enum NativePayloadKey {
    static let action = "action"
    static let operation = "operation"
    static let phase = "phase"
    static let displayName = "displayName"
}

private enum EditorOperationPhase: String {
    case started
    case completed
    case superseded
    case cancelled
    case failed
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

extension EditorBridgeEnvelope where MessageType == NativeToEditorMessageType, Payload == BridgeJSONValue {
    init(
        requestId: UUID = UUID(),
        type: MessageType,
        payload: Payload
    ) throws {
        self.protocolVersion = Self.protocolVersion
        self.requestId = requestId
        self.type = type
        self.payload = payload
        try validatePayloadSize()
        try validatePayload()
    }

    func encodedData() throws -> Data {
        try validatePayload()
        return try JSONEncoder().encode(self)
    }

    static func historyAction(
        _ action: EditorHistoryAction,
        requestId: UUID = UUID()
    ) throws -> Self {
        try Self(
            requestId: requestId,
            type: .performHistoryAction,
            payload: .object([
                NativePayloadKey.action: .string(
                    action.rawValue
                ),
            ])
        )
    }

    static func operationStatus(
        requestId: UUID,
        status: EditorOperationStatus
    ) throws -> Self {
        let operation: EditorOutputOperation
        let phase: EditorOperationPhase
        let displayName: String?

        switch status {
        case let .started(value):
            operation = value
            phase = .started
            displayName = nil
        case .saveCompleted:
            operation = .save
            phase = .completed
            displayName = nil
        case .saveSuperseded:
            operation = .save
            phase = .superseded
            displayName = nil
        case let .exportCompleted(value):
            operation = .export
            phase = .completed
            displayName = value
        case let .cancelled(value):
            operation = value
            phase = .cancelled
            displayName = nil
        case let .failed(value):
            operation = value
            phase = .failed
            displayName = nil
        }

        var payload: [String: BridgeJSONValue] = [
            NativePayloadKey.operation: .string(
                operation.rawValue
            ),
            NativePayloadKey.phase: .string(phase.rawValue),
        ]
        if let displayName {
            payload[NativePayloadKey.displayName] = .string(
                displayName
            )
        }
        return try Self(
            requestId: requestId,
            type: .operationStatus,
            payload: .object(payload)
        )
    }

    static func decode(from data: Data) throws -> Self {
        guard
            let object = try JSONSerialization.jsonObject(
                with: data
            ) as? [String: Any],
            Set(object.keys) == [
                "protocolVersion",
                "requestId",
                "type",
                "payload",
            ]
        else {
            throw EditorBridgeEnvelopeError.malformedMessage
        }
        let envelope = try JSONDecoder().decode(Self.self, from: data)
        try envelope.validatePayload()
        return envelope
    }

    private func validatePayload() throws {
        guard case let .object(payload) = payload else {
            throw EditorBridgeEnvelopeError.malformedMessage
        }
        let exact: (Set<String>) -> Bool = {
            Set(payload.keys) == $0
        }
        switch type {
        case
            .loadDocument,
            .saveCompleted,
            .saveFailed,
            .requestComposite,
            .setAppearance:
            return
        case .performHistoryAction:
            guard
                exact([NativePayloadKey.action]),
                case let .string(action)? = payload[
                    NativePayloadKey.action
                ],
                EditorHistoryAction(rawValue: action) != nil
            else {
                throw EditorBridgeEnvelopeError.malformedMessage
            }
        case .operationStatus:
            guard
                case let .string(operationValue)? = payload[
                    NativePayloadKey.operation
                ],
                let operation = EditorOutputOperation(
                    rawValue: operationValue
                ),
                case let .string(phaseValue)? = payload[
                    NativePayloadKey.phase
                ],
                let phase = EditorOperationPhase(rawValue: phaseValue)
            else {
                throw EditorBridgeEnvelopeError.malformedMessage
            }
            switch (operation, phase) {
            case
                (.save, .started),
                (.export, .started),
                (.save, .completed),
                (.save, .superseded),
                (.save, .cancelled),
                (.export, .cancelled),
                (.save, .failed),
                (.export, .failed):
                guard exact([
                    NativePayloadKey.operation,
                    NativePayloadKey.phase,
                ]) else {
                    throw EditorBridgeEnvelopeError.malformedMessage
                }
            case (.export, .completed):
                guard
                    exact([
                        NativePayloadKey.operation,
                        NativePayloadKey.phase,
                        NativePayloadKey.displayName,
                    ]),
                    case .string = payload[
                        NativePayloadKey.displayName
                    ]
                else {
                    throw EditorBridgeEnvelopeError.malformedMessage
                }
            default:
                throw EditorBridgeEnvelopeError.malformedMessage
            }
        }
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
        case .historyStateChanged:
            guard
                exact(["canUndo", "canRedo"]),
                case .bool = payload["canUndo"],
                case .bool = payload["canRedo"]
            else {
                throw EditorBridgeEnvelopeError.malformedMessage
            }
        case .editorPreferencesChanged:
            guard exact(["tool", "defaults"]),
                  case let .string(tool)? = payload["tool"],
                  ["selection", "rectangle", "arrow", "line", "text", "freehand", "highlighter", "blur", "redaction", "numberMarker"].contains(tool),
                  case let .object(defaults)? = payload["defaults"],
                  Set(defaults.keys) == [
                    "color",
                    "strokeWidth",
                    "textSize",
                    "roughness",
                    "opacity",
                    "rectangleFillColor",
                    "highlighterOpacity",
                  ],
                  case let .string(color)? = defaults["color"],
                  ["#000000", "#FF4D4F", "#1677FF", "#FADB14"].contains(color),
                  let strokeWidth = integer(defaults["strokeWidth"]), [2, 4, 8].contains(strokeWidth),
                  let textSize = integer(defaults["textSize"]), [16, 24, 36].contains(textSize),
                  let roughness = integer(defaults["roughness"]), [0, 1, 2].contains(roughness),
                  case let .number(opacity)? = defaults["opacity"], [0.25, 0.5, 0.75, 1].contains(opacity),
                  defaults["rectangleFillColor"] == .null
                    || validPaletteString(
                        defaults["rectangleFillColor"]
                    ),
                  case let .number(highlighterOpacity)? = defaults["highlighterOpacity"],
                  [0.25, 0.5].contains(highlighterOpacity)
            else { throw EditorBridgeEnvelopeError.malformedMessage }
        case .annotationSnapshot:
            guard
                exact(["document"]),
                case let .object(document)? = payload["document"]
            else { throw EditorBridgeEnvelopeError.malformedMessage }
            do {
                let data = try JSONEncoder().encode(
                    BridgeJSONValue.object(document)
                )
                try EditorDocumentValidator.validate(data)
            } catch {
                throw EditorBridgeEnvelopeError.malformedMessage
            }
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

    private func validPaletteString(
        _ value: BridgeJSONValue?
    ) -> Bool {
        guard case let .string(color)? = value else {
            return false
        }
        return [
            "#000000",
            "#FF4D4F",
            "#1677FF",
            "#FADB14",
        ].contains(color)
    }
}

typealias NativeToEditorEnvelope = EditorBridgeEnvelope<NativeToEditorMessageType, BridgeJSONValue>
typealias EditorToNativeEnvelope = EditorBridgeEnvelope<EditorToNativeMessageType, BridgeJSONValue>
