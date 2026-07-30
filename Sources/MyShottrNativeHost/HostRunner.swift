import Foundation
import ImageIO
import UniformTypeIdentifiers

struct HostRunner {
    private static let maximumImageLength = 45 * 1024 * 1024
    private static let allowedMessageKeys: Set<String> = [
        "protocolVersion",
        "type",
        "captureMode",
        "mimeType",
        "dataBase64",
    ]

    private let staging: any HostCaptureStaging
    private let activator: any AppActivating

    init(
        staging: any HostCaptureStaging,
        activator: any AppActivating
    ) {
        self.staging = staging
        self.activator = activator
    }

    func run(input: FileHandle, output: FileHandle) {
        let reply: NativeHostReply
        do {
            let messageData = try NativeMessageFraming.read(from: input)
            reply = handle(messageData)
        } catch {
            reply = failure(.invalidMessage)
        }

        do {
            let encodedReply = try JSONEncoder().encode(reply)
            try NativeMessageFraming.writeReply(encodedReply, to: output)
        } catch {
            writeDiagnostic("native host could not write reply")
        }
    }

    private func handle(_ messageData: Data) -> NativeHostReply {
        guard
            let object = try? JSONSerialization.jsonObject(with: messageData),
            let dictionary = object as? [String: Any],
            Set(dictionary.keys) == Self.allowedMessageKeys,
            let message = try? JSONDecoder().decode(
                NativeCaptureMessage.self,
                from: messageData
            ),
            message.protocolVersion == 1,
            message.type == "capture"
        else {
            return failure(.invalidMessage)
        }

        guard message.captureMode == .visibleViewport else {
            return failure(.unsupportedCaptureMode)
        }
        guard message.mimeType == "image/png" else {
            return failure(.invalidImage)
        }

        guard let decodedLength = strictBase64DecodedLength(message.dataBase64) else {
            return failure(.invalidImage)
        }
        guard decodedLength <= Self.maximumImageLength else {
            return failure(.imageTooLarge)
        }
        guard
            let imageData = Data(base64Encoded: message.dataBase64),
            isValidPNG(imageData)
        else {
            return failure(.invalidImage)
        }

        let captureID: UUID
        do {
            captureID = try staging.stage(pngData: imageData)
        } catch {
            return failure(.stagingFailed)
        }

        do {
            try activator.activateContainingApp()
        } catch {
            return failure(.stagingFailed)
        }

        return NativeHostReply(ok: true, captureId: captureID, code: nil)
    }

    private func strictBase64DecodedLength(_ value: String) -> Int? {
        let byteCount = value.utf8.count
        guard byteCount > 0, byteCount.isMultiple(of: 4) else {
            return nil
        }

        var index = 0
        var paddingCount = 0
        var finalSextet: UInt8?
        for byte in value.utf8 {
            if byte == 61 {
                guard index >= byteCount - 2 else {
                    return nil
                }
                paddingCount += 1
            } else {
                guard paddingCount == 0, let sextet = base64Value(byte) else {
                    return nil
                }
                finalSextet = sextet
            }
            index += 1
        }
        guard paddingCount <= 2 else {
            return nil
        }
        if paddingCount == 1, let finalSextet, finalSextet & 0b11 != 0 {
            return nil
        }
        if paddingCount == 2, let finalSextet, finalSextet & 0b1111 != 0 {
            return nil
        }

        return byteCount / 4 * 3 - paddingCount
    }

    private func base64Value(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 65...90:
            byte - 65
        case 97...122:
            byte - 97 + 26
        case 48...57:
            byte - 48 + 52
        case 43:
            62
        case 47:
            63
        default:
            nil
        }
    }

    private func isValidPNG(_ data: Data) -> Bool {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let sourceType = CGImageSourceGetType(source),
            sourceType as String == UTType.png.identifier,
            CGImageSourceGetCount(source) == 1,
            CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else {
            return false
        }
        return true
    }

    private func failure(_ code: NativeHostErrorCode) -> NativeHostReply {
        NativeHostReply(ok: false, captureId: nil, code: code)
    }

    private func writeDiagnostic(_ message: String) {
        guard let data = "\(message)\n".data(using: .utf8) else {
            return
        }
        try? FileHandle.standardError.write(contentsOf: data)
    }
}
