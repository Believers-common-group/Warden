import Foundation

public struct WardenStoreTail: Sendable, Equatable {
    public let lastSequence: UInt64
    public let lastEventHash: String?

    public init(lastSequence: UInt64, lastEventHash: String?) {
        self.lastSequence = lastSequence
        self.lastEventHash = lastEventHash
    }
}

public enum WardenStoreAppendResult: Sendable, Equatable {
    case appended
    case queueFull(limit: Int)
    case appendedAfterDeadLettering(eventID: String)
}

public enum WardenStoreIntegrityError: Error, Sendable, Equatable, LocalizedError {
    case invalidEventHash(eventID: String)
    case invalidSequence(expected: UInt64, actual: UInt64)
    case invalidPreviousHash(sequence: UInt64)
    case missingChainAnchor(eventID: String)
    case mismatchedChainAnchor(eventID: String)
    case invalidTail
    case duplicatePendingEvent(eventID: String)

    public var errorDescription: String? {
        switch self {
        case .invalidEventHash(let eventID):
            return "Event \(eventID) failed canonical hash verification."
        case .invalidSequence(let expected, let actual):
            return "The chain expected sequence \(expected) but found \(actual)."
        case .invalidPreviousHash(let sequence):
            return "The previous-hash link is invalid at sequence \(sequence)."
        case .missingChainAnchor(let eventID):
            return "Event \(eventID) does not have a chain anchor."
        case .mismatchedChainAnchor(let eventID):
            return "Event \(eventID) does not match its chain anchor."
        case .invalidTail:
            return "The persisted chain tail does not match the anchor ledger."
        case .duplicatePendingEvent(let eventID):
            return "Pending event \(eventID) is duplicated."
        }
    }
}

public protocol WardenEventStore: Sendable {
    func tail() async -> WardenStoreTail
    func append(
        _ record: WardenStoredRecord,
        maximumQueueSize: Int,
        overflowPolicy: WardenQueueOverflowPolicy
    ) async throws -> WardenStoreAppendResult
    func readyBatch(limit: Int, now: Date) async -> [WardenStoredRecord]
    func acknowledge(_ receipts: [WardenReceipt]) async throws
    func reschedule(
        eventIDs: [String],
        nextAttemptAt: Date,
        failure: String
    ) async throws
    func deadLetter(eventID: String, code: String, reason: String) async throws
    func snapshot() async -> WardenQueueSnapshot
    func pendingEvents() async -> [WardenStoredRecord]
    func deadLetters() async -> [WardenDeadLetter]
    func receipts() async -> [WardenReceipt]
    func chainAnchors() async -> [WardenChainAnchor]
}

public actor WardenMemoryEventStore: WardenEventStore {
    private var core: WardenStoreCore

    public init(maximumStoredReceipts: Int = 10_000) {
        self.core = WardenStoreCore(maximumStoredReceipts: maximumStoredReceipts)
    }

    public func tail() -> WardenStoreTail { core.tail }

    public func append(
        _ record: WardenStoredRecord,
        maximumQueueSize: Int,
        overflowPolicy: WardenQueueOverflowPolicy
    ) throws -> WardenStoreAppendResult {
        try core.append(
            record,
            maximumQueueSize: maximumQueueSize,
            overflowPolicy: overflowPolicy
        )
    }

    public func readyBatch(limit: Int, now: Date) -> [WardenStoredRecord] {
        core.readyBatch(limit: limit, now: now)
    }

    public func acknowledge(_ receipts: [WardenReceipt]) {
        core.acknowledge(receipts)
    }

    public func reschedule(
        eventIDs: [String],
        nextAttemptAt: Date,
        failure: String
    ) {
        core.reschedule(eventIDs: eventIDs, nextAttemptAt: nextAttemptAt, failure: failure)
    }

    public func deadLetter(eventID: String, code: String, reason: String) {
        core.deadLetter(eventID: eventID, code: code, reason: reason)
    }

    public func snapshot() -> WardenQueueSnapshot { core.snapshot }
    public func pendingEvents() -> [WardenStoredRecord] { core.state.pending }
    public func deadLetters() -> [WardenDeadLetter] { core.state.deadLetters }
    public func receipts() -> [WardenReceipt] { core.state.receipts }
    public func chainAnchors() -> [WardenChainAnchor] { core.state.anchors }
}

public actor WardenFileEventStore: WardenEventStore {
    private let fileURL: URL
    private let protector: any WardenPayloadProtector
    private var core: WardenStoreCore

    public init(
        fileURL: URL,
        protector: any WardenPayloadProtector,
        maximumStoredReceipts: Int = 10_000
    ) throws {
        self.fileURL = fileURL
        self.protector = protector
        let state = try Self.loadState(fileURL: fileURL, protector: protector)
        try WardenStoreCore.validate(state)
        self.core = WardenStoreCore(
            state: state,
            maximumStoredReceipts: maximumStoredReceipts
        )
    }

    public func tail() -> WardenStoreTail { core.tail }

    public func append(
        _ record: WardenStoredRecord,
        maximumQueueSize: Int,
        overflowPolicy: WardenQueueOverflowPolicy
    ) throws -> WardenStoreAppendResult {
        var candidate = core
        let result = try candidate.append(
            record,
            maximumQueueSize: maximumQueueSize,
            overflowPolicy: overflowPolicy
        )
        try persist(candidate.state)
        core = candidate
        return result
    }

    public func readyBatch(limit: Int, now: Date) -> [WardenStoredRecord] {
        core.readyBatch(limit: limit, now: now)
    }

    public func acknowledge(_ receipts: [WardenReceipt]) throws {
        var candidate = core
        candidate.acknowledge(receipts)
        try persist(candidate.state)
        core = candidate
    }

    public func reschedule(
        eventIDs: [String],
        nextAttemptAt: Date,
        failure: String
    ) throws {
        var candidate = core
        candidate.reschedule(eventIDs: eventIDs, nextAttemptAt: nextAttemptAt, failure: failure)
        try persist(candidate.state)
        core = candidate
    }

    public func deadLetter(eventID: String, code: String, reason: String) throws {
        var candidate = core
        candidate.deadLetter(eventID: eventID, code: code, reason: reason)
        try persist(candidate.state)
        core = candidate
    }

    public func snapshot() -> WardenQueueSnapshot { core.snapshot }
    public func pendingEvents() -> [WardenStoredRecord] { core.state.pending }
    public func deadLetters() -> [WardenDeadLetter] { core.state.deadLetters }
    public func receipts() -> [WardenReceipt] { core.state.receipts }
    public func chainAnchors() -> [WardenChainAnchor] { core.state.anchors }

    private func persist(_ state: WardenStoreState) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        let plaintext = try WardenCanonicalJSON.encoder().encode(state)
        let protected = try protector.seal(plaintext)
        try protected.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private static func loadState(
        fileURL: URL,
        protector: any WardenPayloadProtector
    ) throws -> WardenStoreState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return WardenStoreState()
        }
        let protected = try Data(contentsOf: fileURL)
        let plaintext = try protector.open(protected)
        return try WardenCanonicalJSON.decoder().decode(WardenStoreState.self, from: plaintext)
    }
}

internal struct WardenStoreState: Codable, Sendable {
    var pending: [WardenStoredRecord]
    var deadLetters: [WardenDeadLetter]
    var receipts: [WardenReceipt]
    var anchors: [WardenChainAnchor]
    var lastSequence: UInt64
    var lastEventHash: String?

    init(
        pending: [WardenStoredRecord] = [],
        deadLetters: [WardenDeadLetter] = [],
        receipts: [WardenReceipt] = [],
        anchors: [WardenChainAnchor] = [],
        lastSequence: UInt64 = 0,
        lastEventHash: String? = nil
    ) {
        self.pending = pending
        self.deadLetters = deadLetters
        self.receipts = receipts
        self.anchors = anchors
        self.lastSequence = lastSequence
        self.lastEventHash = lastEventHash
    }

    private enum CodingKeys: String, CodingKey {
        case pending
        case deadLetters
        case receipts
        case anchors
        case lastSequence
        case lastEventHash
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pending = try container.decodeIfPresent([WardenStoredRecord].self, forKey: .pending) ?? []
        deadLetters = try container.decodeIfPresent([WardenDeadLetter].self, forKey: .deadLetters) ?? []
        receipts = try container.decodeIfPresent([WardenReceipt].self, forKey: .receipts) ?? []
        anchors = try container.decodeIfPresent([WardenChainAnchor].self, forKey: .anchors) ?? []
        lastSequence = try container.decodeIfPresent(UInt64.self, forKey: .lastSequence) ?? 0
        lastEventHash = try container.decodeIfPresent(String.self, forKey: .lastEventHash)
    }
}

internal struct WardenStoreCore: Sendable {
    var state: WardenStoreState
    let maximumStoredReceipts: Int

    init(
        state: WardenStoreState = WardenStoreState(),
        maximumStoredReceipts: Int
    ) {
        self.state = state
        self.maximumStoredReceipts = max(0, maximumStoredReceipts)
    }

    var tail: WardenStoreTail {
        WardenStoreTail(
            lastSequence: state.lastSequence,
            lastEventHash: state.lastEventHash
        )
    }

    var snapshot: WardenQueueSnapshot {
        WardenQueueSnapshot(
            pending: state.pending.count,
            deadLetters: state.deadLetters.count,
            receipts: state.receipts.count,
            lastSequence: state.lastSequence,
            chainAnchors: state.anchors.count
        )
    }

    mutating func append(
        _ record: WardenStoredRecord,
        maximumQueueSize: Int,
        overflowPolicy: WardenQueueOverflowPolicy
    ) throws -> WardenStoreAppendResult {
        let event = record.event
        guard event.hasValidCanonicalHash() else {
            throw WardenStoreIntegrityError.invalidEventHash(eventID: event.id)
        }
        let expectedSequence = state.lastSequence + 1
        guard event.sequence == expectedSequence else {
            throw WardenStoreIntegrityError.invalidSequence(
                expected: expectedSequence,
                actual: event.sequence
            )
        }
        guard event.previousEventHash == state.lastEventHash else {
            throw WardenStoreIntegrityError.invalidPreviousHash(sequence: event.sequence)
        }

        let limit = max(1, maximumQueueSize)
        if state.pending.count >= limit {
            switch overflowPolicy {
            case .rejectNewest:
                return .queueFull(limit: limit)
            case .deadLetterOldest:
                let oldest = state.pending.removeFirst()
                state.deadLetters.append(
                    WardenDeadLetter(
                        event: oldest.event,
                        reasonCode: "queue_overflow",
                        reason: "Removed to admit a newer event because the queue reached \(limit)."
                    )
                )
                state.pending.append(record)
                appendAnchor(for: event)
                return .appendedAfterDeadLettering(eventID: oldest.event.id)
            }
        }

        state.pending.append(record)
        appendAnchor(for: event)
        return .appended
    }

    func readyBatch(limit: Int, now: Date) -> [WardenStoredRecord] {
        state.pending
            .filter { $0.nextAttemptAt <= now }
            .sorted {
                if $0.event.sequence == $1.event.sequence {
                    return $0.enqueuedAt < $1.enqueuedAt
                }
                return $0.event.sequence < $1.event.sequence
            }
            .prefix(max(1, limit))
            .map { $0 }
    }

    mutating func acknowledge(_ receipts: [WardenReceipt]) {
        let acceptedIDs = Set(receipts.map(\.eventID))
        state.pending.removeAll { acceptedIDs.contains($0.event.id) }
        state.receipts.append(contentsOf: receipts)
        if maximumStoredReceipts == 0 {
            state.receipts.removeAll(keepingCapacity: false)
        } else if state.receipts.count > maximumStoredReceipts {
            state.receipts.removeFirst(state.receipts.count - maximumStoredReceipts)
        }
    }

    mutating func reschedule(
        eventIDs: [String],
        nextAttemptAt: Date,
        failure: String
    ) {
        let ids = Set(eventIDs)
        for index in state.pending.indices where ids.contains(state.pending[index].event.id) {
            state.pending[index].attemptCount += 1
            state.pending[index].nextAttemptAt = nextAttemptAt
            state.pending[index].lastFailure = failure
        }
    }

    mutating func deadLetter(eventID: String, code: String, reason: String) {
        guard let index = state.pending.firstIndex(where: { $0.event.id == eventID }) else {
            return
        }
        let record = state.pending.remove(at: index)
        state.deadLetters.append(
            WardenDeadLetter(
                event: record.event,
                reasonCode: code,
                reason: reason
            )
        )
    }

    static func validate(_ state: WardenStoreState) throws {
        var expectedSequence: UInt64 = 1
        var previousHash: String?
        var anchorByID: [String: WardenChainAnchor] = [:]

        for anchor in state.anchors {
            guard anchor.sequence == expectedSequence else {
                throw WardenStoreIntegrityError.invalidSequence(
                    expected: expectedSequence,
                    actual: anchor.sequence
                )
            }
            guard anchor.previousEventHash == previousHash else {
                throw WardenStoreIntegrityError.invalidPreviousHash(sequence: anchor.sequence)
            }
            anchorByID[anchor.eventID] = anchor
            expectedSequence += 1
            previousHash = anchor.eventHash
        }

        let expectedLastSequence = state.anchors.last?.sequence ?? 0
        let expectedLastHash = state.anchors.last?.eventHash
        guard state.lastSequence == expectedLastSequence,
              state.lastEventHash == expectedLastHash else {
            throw WardenStoreIntegrityError.invalidTail
        }

        let pendingIDs = state.pending.map { $0.event.id }
        if Set(pendingIDs).count != pendingIDs.count,
           let duplicate = pendingIDs.first(where: { id in pendingIDs.filter { $0 == id }.count > 1 }) {
            throw WardenStoreIntegrityError.duplicatePendingEvent(eventID: duplicate)
        }

        let retainedEvents = state.pending.map(\.event) + state.deadLetters.map(\.event)
        for event in retainedEvents {
            guard event.hasValidCanonicalHash() else {
                throw WardenStoreIntegrityError.invalidEventHash(eventID: event.id)
            }
            guard let anchor = anchorByID[event.id] else {
                throw WardenStoreIntegrityError.missingChainAnchor(eventID: event.id)
            }
            guard anchor.sequence == event.sequence,
                  anchor.eventHash == event.eventHash,
                  anchor.previousEventHash == event.previousEventHash else {
                throw WardenStoreIntegrityError.mismatchedChainAnchor(eventID: event.id)
            }
        }
    }

    private mutating func appendAnchor(for event: WardenEvent) {
        state.anchors.append(
            WardenChainAnchor(
                sequence: event.sequence,
                eventID: event.id,
                eventHash: event.eventHash,
                previousEventHash: event.previousEventHash,
                recordedAt: event.recordedAt
            )
        )
        state.lastSequence = event.sequence
        state.lastEventHash = event.eventHash
    }
}
