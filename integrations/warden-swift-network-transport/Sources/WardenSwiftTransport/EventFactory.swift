import Foundation

public enum WardenLogRejection: Sendable, Equatable {
    case missingPurpose
    case missingAuthority
    case missingTenantID
    case missingDeviceID
    case missingProjectID
    case missingEventSignature
    case queueFull(limit: Int)
    case eventConstructionFailure(String)
    case persistenceFailure(String)
}

public enum WardenLogResult: Sendable, Equatable {
    case accepted(eventID: String, sequence: UInt64)
    case rejected(WardenLogRejection)
}

internal struct WardenEventFactory: Sendable {
    private let signer: (any WardenEventSigner)?

    init(signer: (any WardenEventSigner)?) {
        self.signer = signer
    }

    func makeEvent(
        request: WardenLogRequest,
        configuration: WardenConfiguration,
        metadata: [String: String],
        sequence: UInt64,
        previousEventHash: String?,
        now: Date
    ) throws -> WardenEvent {
        let id = UUID().uuidString.lowercased()
        let material = WardenUnsignedEvent(
            schemaVersion: 2,
            id: id,
            type: request.type,
            occurredAt: request.occurredAt,
            recordedAt: now,
            tenantID: request.tenantID ?? configuration.defaultTenantID,
            actorID: request.actorID ?? configuration.defaultActorID,
            deviceID: request.deviceID ?? configuration.defaultDeviceID,
            projectID: request.projectID ?? configuration.defaultProjectID,
            appBundle: request.appBundle ?? configuration.defaultAppBundle,
            purpose: request.purpose,
            authority: request.authority,
            policyDecision: request.policyDecision,
            retentionClass: request.retentionClass,
            metadata: metadata,
            evidence: request.evidence,
            sequence: sequence,
            previousEventHash: previousEventHash
        )

        let canonical = try WardenCanonicalJSON.encoder().encode(material)
        let digest = WardenDigest.sha256(canonical)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        let signature = try signer?.sign(eventHash: digest)

        return WardenEvent(
            schemaVersion: material.schemaVersion,
            id: material.id,
            type: material.type,
            occurredAt: material.occurredAt,
            recordedAt: material.recordedAt,
            tenantID: material.tenantID,
            actorID: material.actorID,
            deviceID: material.deviceID,
            projectID: material.projectID,
            appBundle: material.appBundle,
            purpose: material.purpose,
            authority: material.authority,
            policyDecision: material.policyDecision,
            retentionClass: material.retentionClass,
            metadata: material.metadata,
            evidence: material.evidence,
            sequence: material.sequence,
            previousEventHash: material.previousEventHash,
            eventHash: hash,
            signature: signature
        )
    }
}

private struct WardenUnsignedEvent: Codable, Sendable {
    let schemaVersion: Int
    let id: String
    let type: WardenEventType
    let occurredAt: Date
    let recordedAt: Date
    let tenantID: String?
    let actorID: String?
    let deviceID: String?
    let projectID: String?
    let appBundle: String?
    let purpose: String
    let authority: WardenAuthority
    let policyDecision: WardenPolicyDecision
    let retentionClass: String
    let metadata: [String: String]
    let evidence: [WardenEvidenceReference]
    let sequence: UInt64
    let previousEventHash: String?
}

public extension WardenEvent {
    func hasValidCanonicalHash() -> Bool {
        let material = WardenUnsignedEvent(
            schemaVersion: schemaVersion,
            id: id,
            type: type,
            occurredAt: occurredAt,
            recordedAt: recordedAt,
            tenantID: tenantID,
            actorID: actorID,
            deviceID: deviceID,
            projectID: projectID,
            appBundle: appBundle,
            purpose: purpose,
            authority: authority,
            policyDecision: policyDecision,
            retentionClass: retentionClass,
            metadata: metadata,
            evidence: evidence,
            sequence: sequence,
            previousEventHash: previousEventHash
        )
        guard let canonical = try? WardenCanonicalJSON.encoder().encode(material) else {
            return false
        }
        return WardenDigest.sha256Hex(canonical) == eventHash
    }
}
