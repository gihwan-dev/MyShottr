import CryptoKit
import Foundation

enum ChromeExtensionIdentityError: Error {
    case invalidPublicKey
}

enum ChromeExtensionIdentity {
    static func id(fromBase64DER value: String) throws -> String {
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard
            !normalized.isEmpty,
            let publicKey = Data(base64Encoded: normalized)
        else {
            throw ChromeExtensionIdentityError.invalidPublicKey
        }

        let digest = SHA256.hash(data: publicKey)
        let alphabet = Array("abcdefghijklmnop".utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(32)

        for byte in digest.prefix(16) {
            bytes.append(alphabet[Int(byte >> 4)])
            bytes.append(alphabet[Int(byte & 0x0F)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
