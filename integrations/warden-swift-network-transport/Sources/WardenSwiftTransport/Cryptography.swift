import Foundation

public enum WardenCryptographyError: Error, Sendable, Equatable {
    case invalidKey
    case protectionUnavailable
    case invalidProtectedPayload
}

public protocol WardenEventSigner: Sendable {
    func sign(eventHash: Data) throws -> WardenSignature
}

public struct WardenHMACSHA256Signer: WardenEventSigner, Sendable {
    private let key: Data
    private let keyID: String

    public init(key: Data, keyID: String) throws {
        guard !key.isEmpty, !keyID.isEmpty else {
            throw WardenCryptographyError.invalidKey
        }
        self.key = key
        self.keyID = keyID
    }

    public func sign(eventHash: Data) throws -> WardenSignature {
        let value = WardenSHA256.hmac(key: key, message: eventHash).base64EncodedString()
        return WardenSignature(
            algorithm: "hmac-sha256",
            keyID: keyID,
            value: value
        )
    }
}

public protocol WardenPayloadProtector: Sendable {
    func seal(_ plaintext: Data) throws -> Data
    func open(_ protectedData: Data) throws -> Data
}

/// Development and test only. Production clients should inject an authenticated
/// encryption protector such as `WardenAESGCMProtector` on Apple platforms.
public struct WardenUnprotectedPayloadProtector: WardenPayloadProtector, Sendable {
    public init() {}

    public func seal(_ plaintext: Data) throws -> Data { plaintext }
    public func open(_ protectedData: Data) throws -> Data { protectedData }
}

#if canImport(CryptoKit)
import CryptoKit

public struct WardenAESGCMProtector: WardenPayloadProtector, Sendable {
    private let key: SymmetricKey

    public init(keyData: Data) throws {
        guard [16, 24, 32].contains(keyData.count) else {
            throw WardenCryptographyError.invalidKey
        }
        self.key = SymmetricKey(data: keyData)
    }

    public func seal(_ plaintext: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else {
            throw WardenCryptographyError.invalidProtectedPayload
        }
        return combined
    }

    public func open(_ protectedData: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: protectedData)
        return try AES.GCM.open(box, using: key)
    }
}
#endif

public enum WardenCanonicalJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

public enum WardenDigest {
    public static func sha256(_ data: Data) -> Data {
        WardenSHA256.hash(data)
    }

    public static func sha256Hex(_ data: Data) -> String {
        WardenSHA256.hash(data).hexLowercased
    }
}

internal enum WardenSHA256 {
    private static let initialHash: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]

    private static let constants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func hash(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        let bitLength = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 {
            bytes.append(0)
        }
        bytes.append(contentsOf: withUnsafeBytes(of: bitLength.bigEndian, Array.init))

        var hash = initialHash
        var words = [UInt32](repeating: 0, count: 64)

        for offset in stride(from: 0, to: bytes.count, by: 64) {
            for index in 0..<16 {
                let position = offset + index * 4
                words[index] = UInt32(bytes[position]) << 24
                    | UInt32(bytes[position + 1]) << 16
                    | UInt32(bytes[position + 2]) << 8
                    | UInt32(bytes[position + 3])
            }

            for index in 16..<64 {
                let s0 = rotateRight(words[index - 15], by: 7)
                    ^ rotateRight(words[index - 15], by: 18)
                    ^ (words[index - 15] >> 3)
                let s1 = rotateRight(words[index - 2], by: 17)
                    ^ rotateRight(words[index - 2], by: 19)
                    ^ (words[index - 2] >> 10)
                words[index] = words[index - 16]
                    &+ s0
                    &+ words[index - 7]
                    &+ s1
            }

            var a = hash[0]
            var b = hash[1]
            var c = hash[2]
            var d = hash[3]
            var e = hash[4]
            var f = hash[5]
            var g = hash[6]
            var h = hash[7]

            for index in 0..<64 {
                let sum1 = rotateRight(e, by: 6)
                    ^ rotateRight(e, by: 11)
                    ^ rotateRight(e, by: 25)
                let choice = (e & f) ^ ((~e) & g)
                let temporary1 = h
                    &+ sum1
                    &+ choice
                    &+ constants[index]
                    &+ words[index]
                let sum0 = rotateRight(a, by: 2)
                    ^ rotateRight(a, by: 13)
                    ^ rotateRight(a, by: 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temporary2 = sum0 &+ majority

                h = g
                g = f
                f = e
                e = d &+ temporary1
                d = c
                c = b
                b = a
                a = temporary1 &+ temporary2
            }

            hash[0] = hash[0] &+ a
            hash[1] = hash[1] &+ b
            hash[2] = hash[2] &+ c
            hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e
            hash[5] = hash[5] &+ f
            hash[6] = hash[6] &+ g
            hash[7] = hash[7] &+ h
        }

        var result = Data()
        result.reserveCapacity(32)
        for value in hash {
            var bigEndian = value.bigEndian
            withUnsafeBytes(of: &bigEndian) { result.append(contentsOf: $0) }
        }
        return result
    }

    static func hmac(key: Data, message: Data) -> Data {
        let blockSize = 64
        var normalizedKey = [UInt8](key)
        if normalizedKey.count > blockSize {
            normalizedKey = [UInt8](hash(Data(normalizedKey)))
        }
        if normalizedKey.count < blockSize {
            normalizedKey.append(contentsOf: repeatElement(0, count: blockSize - normalizedKey.count))
        }

        let outer = normalizedKey.map { $0 ^ 0x5c }
        let inner = normalizedKey.map { $0 ^ 0x36 }
        let innerHash = hash(Data(inner) + message)
        return hash(Data(outer) + innerHash)
    }

    private static func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}

private extension Data {
    var hexLowercased: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

#if canImport(CryptoKit)
import CryptoKit

/// Production device signer. The server registry stores only the corresponding
/// Ed25519 public key. The signed message is the raw 32-byte SHA-256 event digest.
public struct WardenEd25519EventSigner: WardenEventSigner, Sendable {
    private let privateKeyData: Data
    private let keyID: String

    public init(privateKeyData: Data, keyID: String) throws {
        guard !privateKeyData.isEmpty, !keyID.isEmpty else {
            throw WardenCryptographyError.invalidKey
        }
        _ = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        self.privateKeyData = privateKeyData
        self.keyID = keyID
    }

    public init(keyID: String) throws {
        guard !keyID.isEmpty else { throw WardenCryptographyError.invalidKey }
        let key = Curve25519.Signing.PrivateKey()
        self.privateKeyData = key.rawRepresentation
        self.keyID = keyID
    }

    public var rawPrivateKey: Data { privateKeyData }

    public var rawPublicKey: Data {
        get throws {
            try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
                .publicKey.rawRepresentation
        }
    }

    public func sign(eventHash: Data) throws -> WardenSignature {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        let signature = try key.signature(for: eventHash)
        return WardenSignature(
            algorithm: "ed25519-sha256-digest",
            keyID: keyID,
            value: signature.base64EncodedString()
        )
    }
}
#endif
