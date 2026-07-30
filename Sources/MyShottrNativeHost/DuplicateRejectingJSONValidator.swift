import Foundation

enum DuplicateRejectingJSONValidator {
    static func isValid(_ data: Data) -> Bool {
        var parser = Parser(bytes: Array(data))
        return parser.parseDocument()
    }
}

private struct Parser {
    private let bytes: [UInt8]
    private var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func parseDocument() -> Bool {
        do {
            skipWhitespace()
            try parseValue()
            skipWhitespace()
            return index == bytes.count
        } catch {
            return false
        }
    }

    private mutating func parseValue() throws {
        guard let byte = current else {
            throw ParseError.invalidJSON
        }

        switch byte {
        case 0x7B:
            try parseObject()
        case 0x5B:
            try parseArray()
        case 0x22:
            _ = try parseString()
        case 0x74:
            try consumeLiteral([0x74, 0x72, 0x75, 0x65])
        case 0x66:
            try consumeLiteral([0x66, 0x61, 0x6C, 0x73, 0x65])
        case 0x6E:
            try consumeLiteral([0x6E, 0x75, 0x6C, 0x6C])
        case 0x2D, 0x30...0x39:
            try parseNumber()
        default:
            throw ParseError.invalidJSON
        }
    }

    private mutating func parseObject() throws {
        index += 1
        skipWhitespace()
        if consume(0x7D) {
            return
        }

        var keys = Set<String>()
        while true {
            guard current == 0x22 else {
                throw ParseError.invalidJSON
            }
            let key = try parseString()
            guard keys.insert(key).inserted else {
                throw ParseError.duplicateMember
            }

            skipWhitespace()
            guard consume(0x3A) else {
                throw ParseError.invalidJSON
            }
            skipWhitespace()
            try parseValue()
            skipWhitespace()

            if consume(0x7D) {
                return
            }
            guard consume(0x2C) else {
                throw ParseError.invalidJSON
            }
            skipWhitespace()
        }
    }

    private mutating func parseArray() throws {
        index += 1
        skipWhitespace()
        if consume(0x5D) {
            return
        }

        while true {
            try parseValue()
            skipWhitespace()
            if consume(0x5D) {
                return
            }
            guard consume(0x2C) else {
                throw ParseError.invalidJSON
            }
            skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        guard consume(0x22) else {
            throw ParseError.invalidJSON
        }

        while let byte = current {
            switch byte {
            case 0x00...0x1F:
                throw ParseError.invalidJSON
            case 0x22:
                index += 1
                let encoded = Data(bytes[start..<index])
                guard
                    let decoded = try? JSONSerialization.jsonObject(
                        with: encoded,
                        options: [.fragmentsAllowed]
                    ) as? String
                else {
                    throw ParseError.invalidJSON
                }
                return decoded
            case 0x5C:
                index += 1
                guard current != nil else {
                    throw ParseError.invalidJSON
                }
                index += 1
            default:
                index += 1
            }
        }
        throw ParseError.invalidJSON
    }

    private mutating func parseNumber() throws {
        _ = consume(0x2D)
        guard let byte = current else {
            throw ParseError.invalidJSON
        }

        if byte == 0x30 {
            index += 1
            if let current, (0x30...0x39).contains(current) {
                throw ParseError.invalidJSON
            }
        } else {
            guard (0x31...0x39).contains(byte) else {
                throw ParseError.invalidJSON
            }
            consumeDigits()
        }

        if consume(0x2E) {
            guard consumeDigits() else {
                throw ParseError.invalidJSON
            }
        }
        if current == 0x65 || current == 0x45 {
            index += 1
            if current == 0x2B || current == 0x2D {
                index += 1
            }
            guard consumeDigits() else {
                throw ParseError.invalidJSON
            }
        }
        guard current.map(isValueDelimiter) ?? true else {
            throw ParseError.invalidJSON
        }
    }

    @discardableResult
    private mutating func consumeDigits() -> Bool {
        let start = index
        while let byte = current, (0x30...0x39).contains(byte) {
            index += 1
        }
        return index > start
    }

    private mutating func consumeLiteral(_ literal: [UInt8]) throws {
        guard bytes[index...].starts(with: literal) else {
            throw ParseError.invalidJSON
        }
        index += literal.count
        guard current.map(isValueDelimiter) ?? true else {
            throw ParseError.invalidJSON
        }
    }

    private mutating func skipWhitespace() {
        while let byte = current, [0x20, 0x09, 0x0A, 0x0D].contains(byte) {
            index += 1
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard current == byte else {
            return false
        }
        index += 1
        return true
    }

    private var current: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private func isValueDelimiter(_ byte: UInt8) -> Bool {
        byte == 0x20
            || byte == 0x09
            || byte == 0x0A
            || byte == 0x0D
            || byte == 0x2C
            || byte == 0x5D
            || byte == 0x7D
    }
}

private enum ParseError: Error {
    case duplicateMember
    case invalidJSON
}
