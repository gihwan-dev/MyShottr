import Foundation

enum NativeMessageError: Error, Equatable {
    case truncatedHeader
    case messageTooLarge
    case truncatedMessage
    case replyTooLarge
}

enum NativeMessageFraming {
    static let maximumMessageLength = 64 * 1024 * 1024
    static let maximumReplyLength = 1024 * 1024

    static func read(from data: Data) throws -> Data {
        guard data.count >= 4 else {
            throw NativeMessageError.truncatedHeader
        }

        let declaredLength = Int(
            UInt32(data[0])
                | UInt32(data[1]) << 8
                | UInt32(data[2]) << 16
                | UInt32(data[3]) << 24
        )
        try validateMessageLength(declaredLength)
        guard data.count >= 4 + declaredLength else {
            throw NativeMessageError.truncatedMessage
        }

        return data.subdata(in: 4..<(4 + declaredLength))
    }

    static func read(from input: FileHandle) throws -> Data {
        let header = try readExactly(
            4,
            from: input,
            truncationError: .truncatedHeader
        )
        let declaredLength = Int(
            UInt32(header[0])
                | UInt32(header[1]) << 8
                | UInt32(header[2]) << 16
                | UInt32(header[3]) << 24
        )
        try validateMessageLength(declaredLength)
        return try readExactly(
            declaredLength,
            from: input,
            truncationError: .truncatedMessage
        )
    }

    static func frameReply(_ body: Data) throws -> Data {
        guard body.count <= maximumReplyLength else {
            throw NativeMessageError.replyTooLarge
        }

        var littleEndianLength = UInt32(body.count).littleEndian
        return Data(bytes: &littleEndianLength, count: 4) + body
    }

    static func writeReply(_ body: Data, to output: FileHandle) throws {
        try output.write(contentsOf: frameReply(body))
    }

    private static func validateMessageLength(_ length: Int) throws {
        guard length <= maximumMessageLength else {
            throw NativeMessageError.messageTooLarge
        }
    }

    private static func readExactly(
        _ count: Int,
        from input: FileHandle,
        truncationError: NativeMessageError
    ) throws -> Data {
        var result = Data()
        result.reserveCapacity(count)

        while result.count < count {
            let remaining = count - result.count
            guard
                let chunk = try input.read(upToCount: remaining),
                !chunk.isEmpty
            else {
                throw truncationError
            }
            result.append(chunk)
        }

        return result
    }
}
