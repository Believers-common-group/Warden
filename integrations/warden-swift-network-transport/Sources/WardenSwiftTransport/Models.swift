import Foundation

public struct WardenEventType: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public extension WardenEventType {
    static let productReceived: Self = "product.received"
    static let inventoryTransferred: Self = "inventory.transferred"
    static let productSold: Self = "product.sold"
    static let productReturned: Self = "product.returned"
    static let paymentSettled: Self = "payment.settled"
    static let policyDecision: Self = "policy.decision"
    static let consentChanged: Self = "consent.changed"
}

public struct WardenAuthority: Codable, Hashable, Sendable {
    public enum Basis: String, Codable, Hashable, Sendable {
        case consent
        case contract
        case legalObligation
        case legitimateInterest
        case vitalInterest
        case publicTask
        case systemOperation
        case none
    }

    public let basis: Basis
    public let reference: String?
    public let recordedAt: Date

    public init(
        basis: Basis,
        reference: String? = nil,
        recordedAt: Date = Date()
    ) {
        self.basis = basis
        self.reference = reference
        self.recordedAt = recordedAt
    }
}

public enum WardenPolicyDecision: String, Codable, Hashable, Sendable {
    case allow
    case deny
    case allowWithRedaction
    case notEvaluated
}

public struct WardenEvidenceReference: Codable, Hashable, Sendable {
    public let mediaType: String
    public let digestAlgorithm: String
    public let digest: String
    public let locator: String?

    public init(
        mediaType: String,
        digestAlgorithm: String = "sha256",
        digest: String,
        locator: String? = nil
    ) {
        self.mediaType = mediaType
        self.digestAlgorithm = digestAlgorithm
        self.digest = digest
        self.locator = locator
    }
}

public struct WardenSignature: Codable, Hashable, Sendable {
    public let algorithm: String
    public let keyID: String
    public let value: String

    public init(algorithm: String, keyID: String, value: String) {
        self.algorithm = algorithm
        self.keyID = keyID
        self.value = value
    }
}

public struct WardenEvent: Codable, Hashable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let id: String
    public let type: WardenEventType
    public let occurredAt: Date
    public let recordedAt: Date
    public let tenantID: String?
    public let actorID: String?
    public let deviceID: String?
    public let projectID: String?
    public let appBundle: String?
    public let purpose: String
    public let authority: WardenAuthority
    public let policyDecision: WardenPolicyDecision
    public let retentionClass: String
    public let metadata: [String: String]
    public let evidence: [WardenEvidenceReference]
    public let sequence: UInt64
    public let previousEventHash: String?
    public let eventHash: String
    public let signature: WardenSignature?

    public init(
        schemaVersion: Int = 1,
        id: String,
        type: WardenEventType,
        occurredAt: Date,
        recordedAt: Date,
        tenantID: String?,
        actorID: String?,
        deviceID: String?,
        projectID: String?,
        appBundle: String?,
        purpose: String,
        authority: WardenAuthority,
        policyDecision: WardenPolicyDecision,
        retentionClass: String,
        metadata: [String: String],
        evidence: [WardenEvidenceReference],
        sequence: UInt64,
        previousEventHash: String?,
        eventHash: String,
        signature: WardenSignature?
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.type = type
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
        self.tenantID = tenantID
        self.actorID = actorID
        self.deviceID = deviceID
        self.projectID = projectID
        self.appBundle = appBundle
        self.purpose = purpose
        self.authority = authority
        self.policyDecision = policyDecision
        self.retentionClass = retentionClass
        self.metadata = metadata
        self.evidence = evidence
        self.sequence = sequence
        self.previousEventHash = previousEventHash
        self.eventHash = eventHash
        self.signature = signature
    }
}

public struct WardenLogRequest: Sendable {
    public let type: WardenEventType
    public let occurredAt: Date
    public let tenantID: String?
    public let actorID: String?
    public let deviceID: String?
    public let projectID: String?
    public let appBundle: String?
    public let purpose: String
    public let authority: WardenAuthority
    public let policyDecision: WardenPolicyDecision
    public let retentionClass: String
    public let metadata: [String: String]
    public let evidence: [WardenEvidenceReference]

    public init(
        type: WardenEventType,
        occurredAt: Date = Date(),
        tenantID: String? = nil,
        actorID: String? = nil,
        deviceID: String? = nil,
        projectID: String? = nil,
        appBundle: String? = nil,
        purpose: String,
        authority: WardenAuthority,
        policyDecision: WardenPolicyDecision = .notEvaluated,
        retentionClass: String = "operational",
        metadata: [String: String] = [:],
        evidence: [WardenEvidenceReference] = []
    ) {
        self.type = type
        self.occurredAt = occurredAt
        self.tenantID = tenantID
        self.actorID = actorID
        self.deviceID = deviceID
        self.projectID = projectID
        self.appBundle = appBundle
        self.purpose = purpose
        self.authority = authority
        self.policyDecision = policyDecision
        self.retentionClass = retentionClass
        self.metadata = metadata
        self.evidence = evidence
    }
}

public struct WardenStoredRecord: Codable, Hashable, Sendable {
    public let event: WardenEvent
    public var attemptCount: Int
    public var nextAttemptAt: Date
    public var lastFailure: String?
    public let enqueuedAt: Date

    public init(
        event: WardenEvent,
        attemptCount: Int = 0,
        nextAttemptAt: Date = .distantPast,
        lastFailure: String? = nil,
        enqueuedAt: Date = Date()
    ) {
        self.event = event
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
        self.lastFailure = lastFailure
        self.enqueuedAt = enqueuedAt
    }
}

public struct WardenDeadLetter: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let event: WardenEvent
    public let reasonCode: String
    public let reason: String
    public let recordedAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        event: WardenEvent,
        reasonCode: String,
        reason: String,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.event = event
        self.reasonCode = reasonCode
        self.reason = reason
        self.recordedAt = recordedAt
    }
}

public struct WardenReceipt: Codable, Hashable, Sendable {
    public let eventID: String
    public let receiptID: String
    public let recordedAt: Date
    public let tenantID: String?
    public let projectID: String?
    public let eventHash: String?
    public let ledgerSequence: UInt64?
    public let ledgerEntryHash: String?
    public let policyDecisionID: String?
    public let serverSignature: WardenSignature?

    public init(
        eventID: String,
        receiptID: String,
        recordedAt: Date,
        tenantID: String? = nil,
        projectID: String? = nil,
        eventHash: String? = nil,
        ledgerSequence: UInt64? = nil,
        ledgerEntryHash: String? = nil,
        policyDecisionID: String? = nil,
        serverSignature: WardenSignature? = nil
    ) {
        self.eventID = eventID
        self.receiptID = receiptID
        self.recordedAt = recordedAt
        self.tenantID = tenantID
        self.projectID = projectID
        self.eventHash = eventHash
        self.ledgerSequence = ledgerSequence
        self.ledgerEntryHash = ledgerEntryHash
        self.policyDecisionID = policyDecisionID
        self.serverSignature = serverSignature
    }
}

public struct WardenRejectedEvent: Codable, Hashable, Sendable {
    public let eventID: String
    public let code: String
    public let message: String
    public let retryable: Bool
    public let retryAfterSeconds: TimeInterval?

    public init(
        eventID: String,
        code: String,
        message: String,
        retryable: Bool,
        retryAfterSeconds: TimeInterval? = nil
    ) {
        self.eventID = eventID
        self.code = code
        self.message = message
        self.retryable = retryable
        self.retryAfterSeconds = retryAfterSeconds
    }
}

public struct WardenBatchEnvelope: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let batchID: String
    public let sentAt: Date
    public let tenantID: String?
    public let events: [WardenEvent]

    public init(
        schemaVersion: Int = 2,
        batchID: String = UUID().uuidString.lowercased(),
        sentAt: Date = Date(),
        tenantID: String? = nil,
        events: [WardenEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.batchID = batchID
        self.sentAt = sentAt
        self.tenantID = tenantID
        self.events = events
    }
}

public struct WardenBatchAcknowledgement: Codable, Hashable, Sendable {
    public let batchID: String
    public let accepted: [WardenReceipt]
    public let rejected: [WardenRejectedEvent]

    public init(
        batchID: String,
        accepted: [WardenReceipt],
        rejected: [WardenRejectedEvent]
    ) {
        self.batchID = batchID
        self.accepted = accepted
        self.rejected = rejected
    }
}


public struct WardenChainAnchor: Codable, Hashable, Sendable {
    public let sequence: UInt64
    public let eventID: String
    public let eventHash: String
    public let previousEventHash: String?
    public let recordedAt: Date

    public init(
        sequence: UInt64,
        eventID: String,
        eventHash: String,
        previousEventHash: String?,
        recordedAt: Date
    ) {
        self.sequence = sequence
        self.eventID = eventID
        self.eventHash = eventHash
        self.previousEventHash = previousEventHash
        self.recordedAt = recordedAt
    }
}

public struct WardenQueueSnapshot: Sendable, Equatable {
    public let pending: Int
    public let deadLetters: Int
    public let receipts: Int
    public let lastSequence: UInt64
    public let chainAnchors: Int

    public init(
        pending: Int,
        deadLetters: Int,
        receipts: Int,
        lastSequence: UInt64,
        chainAnchors: Int
    ) {
        self.pending = pending
        self.deadLetters = deadLetters
        self.receipts = receipts
        self.lastSequence = lastSequence
        self.chainAnchors = chainAnchors
    }
}
