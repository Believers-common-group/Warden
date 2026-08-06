import Foundation

public protocol WardenReceiptVerifier: Sendable {
    func verify(receipt: WardenReceipt, event: WardenEvent) -> Bool
}

public extension WardenReceipt {
    /// Canonical receipt claims covered by v2 HMAC and Ed25519 signatures.
    /// `serverSignature` is deliberately excluded.
    func canonicalSigningData() throws -> Data {
        try WardenCanonicalJSON.encoder().encode(
            WardenReceiptSigningClaims(
                eventID: eventID,
                receiptID: receiptID,
                recordedAt: recordedAt,
                tenantID: tenantID,
                projectID: projectID,
                eventHash: eventHash,
                ledgerSequence: ledgerSequence,
                ledgerEntryHash: ledgerEntryHash,
                policyDecisionID: policyDecisionID
            )
        )
    }

    func claimsMatch(event: WardenEvent) -> Bool {
        guard eventID == event.id, !receiptID.isEmpty else { return false }
        if let tenantID, tenantID != event.tenantID { return false }
        if let projectID, projectID != event.projectID { return false }
        if let eventHash, eventHash != event.eventHash { return false }
        if (ledgerSequence == nil) != (ledgerEntryHash == nil) { return false }
        if ledgerEntryHash?.isEmpty == true { return false }
        return true
    }
}

private struct WardenReceiptSigningClaims: Codable, Sendable {
    let eventID: String
    let receiptID: String
    let recordedAt: Date
    let tenantID: String?
    let projectID: String?
    let eventHash: String?
    let ledgerSequence: UInt64?
    let ledgerEntryHash: String?
    let policyDecisionID: String?
}

public struct WardenRejectingReceiptVerifier: WardenReceiptVerifier, Sendable {
    public init() {}

    public func verify(receipt: WardenReceipt, event: WardenEvent) -> Bool {
        false
    }
}

public struct WardenExplicitReceiptVerifier: WardenReceiptVerifier, Sendable {
    public init() {}

    public func verify(receipt: WardenReceipt, event: WardenEvent) -> Bool {
        receipt.claimsMatch(event: event)
    }
}

/// Verifies either the legacy v1 HMAC receipt or the v2 canonical-claims receipt.
/// v2 is preferred because it binds the tenant, project, event hash, policy result,
/// and RiverOS ledger position to the acknowledgement.
public struct WardenHMACReceiptVerifier: WardenReceiptVerifier, Sendable {
    private let key: Data
    private let keyID: String

    public init(key: Data, keyID: String) throws {
        guard !key.isEmpty, !keyID.isEmpty else {
            throw WardenCryptographyError.invalidKey
        }
        self.key = key
        self.keyID = keyID
    }

    public func verify(receipt: WardenReceipt, event: WardenEvent) -> Bool {
        guard receipt.claimsMatch(event: event),
              let signature = receipt.serverSignature,
              signature.keyID == keyID,
              let supplied = Data(base64Encoded: signature.value) else {
            return false
        }

        let material: Data
        switch signature.algorithm {
        case "hmac-sha256-v2":
            guard let canonical = try? receipt.canonicalSigningData() else { return false }
            material = canonical
        case "hmac-sha256":
            let milliseconds = Int64((receipt.recordedAt.timeIntervalSince1970 * 1_000).rounded())
            material = Data("\(receipt.eventID)\n\(receipt.receiptID)\n\(milliseconds)".utf8)
        default:
            return false
        }

        let expected = WardenSHA256.hmac(key: key, message: material)
        return constantTimeEqual(expected, supplied)
    }

    private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }
}

#if canImport(CryptoKit)
import CryptoKit

/// Production receipt verifier for RiverOS Ed25519-signed receipt claims.
public struct WardenEd25519ReceiptVerifier: WardenReceiptVerifier, Sendable {
    private let publicKeyData: Data
    private let keyID: String

    public init(publicKeyData: Data, keyID: String) throws {
        guard !publicKeyData.isEmpty, !keyID.isEmpty else {
            throw WardenCryptographyError.invalidKey
        }
        _ = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        self.publicKeyData = publicKeyData
        self.keyID = keyID
    }

    public func verify(receipt: WardenReceipt, event: WardenEvent) -> Bool {
        guard receipt.claimsMatch(event: event),
              let signature = receipt.serverSignature,
              signature.algorithm == "ed25519-canonical-json-v2",
              signature.keyID == keyID,
              let supplied = Data(base64Encoded: signature.value),
              let canonical = try? receipt.canonicalSigningData(),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            return false
        }
        return publicKey.isValidSignature(supplied, for: canonical)
    }
}
#endif
