import Foundation

public enum WardenFlushDisposition: Sendable, Equatable {
    case noWork, completed, partiallyCompleted, deferred, blocked, alreadyRunning
}

public struct WardenFlushReport: Sendable, Equatable {
    public let disposition: WardenFlushDisposition
    public let attempted: Int
    public let accepted: Int
    public let rescheduled: Int
    public let deadLettered: Int
    public let pendingAfterFlush: Int
    public let message: String?

    public init(
        disposition: WardenFlushDisposition,
        attempted: Int,
        accepted: Int,
        rescheduled: Int,
        deadLettered: Int,
        pendingAfterFlush: Int,
        message: String? = nil
    ) {
        self.disposition = disposition
        self.attempted = attempted
        self.accepted = accepted
        self.rescheduled = rescheduled
        self.deadLettered = deadLettered
        self.pendingAfterFlush = pendingAfterFlush
        self.message = message
    }
}

public actor WardenLogger {
    private var configuration: WardenConfiguration
    private let store: any WardenEventStore
    private let transport: any WardenBatchTransport
    private let credentialProvider: any WardenCredentialProvider
    private let receiptVerifier: any WardenReceiptVerifier
    private let sanitizer: WardenMetadataSanitizer
    private let eventFactory: WardenEventFactory
    private var isFlushing = false

    public init(
        configuration: WardenConfiguration = WardenConfiguration(),
        store: any WardenEventStore,
        transport: any WardenBatchTransport = URLSessionWardenBatchTransport(),
        credentialProvider: any WardenCredentialProvider = WardenNoCredentialProvider(),
        receiptVerifier: any WardenReceiptVerifier = WardenRejectingReceiptVerifier(),
        sanitizer: WardenMetadataSanitizer = WardenMetadataSanitizer(),
        signer: (any WardenEventSigner)? = nil
    ) {
        self.configuration = configuration
        self.store = store
        self.transport = transport
        self.credentialProvider = credentialProvider
        self.receiptVerifier = receiptVerifier
        self.sanitizer = sanitizer
        self.eventFactory = WardenEventFactory(signer: signer)
    }

    public func configure(_ configuration: WardenConfiguration) {
        self.configuration = configuration
    }

    @discardableResult
    public func log(_ request: WardenLogRequest) async -> WardenLogResult {
        guard !request.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .rejected(.missingPurpose)
        }
        if configuration.authorityRequirement == .required, request.authority.basis == .none {
            return .rejected(.missingAuthority)
        }

        let tenantID = request.tenantID ?? configuration.defaultTenantID
        let deviceID = request.deviceID ?? configuration.defaultDeviceID
        let projectID = request.projectID ?? configuration.defaultProjectID
        if configuration.registryIdentityRequirement == .required {
            guard tenantID?.isEmpty == false else { return .rejected(.missingTenantID) }
            guard deviceID?.isEmpty == false else { return .rejected(.missingDeviceID) }
            guard projectID?.isEmpty == false else { return .rejected(.missingProjectID) }
        }

        let tail = await store.tail()
        let event: WardenEvent
        do {
            event = try eventFactory.makeEvent(
                request: request,
                configuration: configuration,
                metadata: sanitizer.sanitize(request.metadata, policy: configuration.metadataPolicy),
                sequence: tail.lastSequence + 1,
                previousEventHash: tail.lastEventHash,
                now: Date()
            )
        } catch {
            return .rejected(.eventConstructionFailure(String(describing: error)))
        }
        if configuration.eventSignatureRequirement == .required, event.signature == nil {
            return .rejected(.missingEventSignature)
        }

        do {
            switch try await store.append(
                WardenStoredRecord(event: event),
                maximumQueueSize: configuration.maximumQueueSize,
                overflowPolicy: configuration.overflowPolicy
            ) {
            case .queueFull(let limit):
                return .rejected(.queueFull(limit: limit))
            case .appended, .appendedAfterDeadLettering:
                if configuration.flushAfterEachEvent { _ = await flush() }
                return .accepted(eventID: event.id, sequence: event.sequence)
            }
        } catch {
            return .rejected(.persistenceFailure(String(describing: error)))
        }
    }

    @discardableResult
    public func log(
        type: WardenEventType,
        purpose: String,
        authority: WardenAuthority,
        policyDecision: WardenPolicyDecision = .notEvaluated,
        retentionClass: String = "operational",
        metadata: [String: String] = [:],
        evidence: [WardenEvidenceReference] = []
    ) async -> WardenLogResult {
        await log(WardenLogRequest(
            type: type,
            purpose: purpose,
            authority: authority,
            policyDecision: policyDecision,
            retentionClass: retentionClass,
            metadata: metadata,
            evidence: evidence
        ))
    }

    public func flush() async -> WardenFlushReport {
        guard !isFlushing else { return await report(.alreadyRunning) }
        guard configuration.transport.allowNetwork, configuration.transport.endpoint != nil else {
            return await report(.blocked, message: "Network delivery or endpoint is unavailable.")
        }

        let candidates = await store.readyBatch(
            limit: configuration.transport.maximumBatchSize,
            now: Date()
        )
        guard let first = candidates.first else {
            let snapshot = await store.snapshot()
            return WardenFlushReport(
                disposition: snapshot.pending == 0 ? .noWork : .deferred,
                attempted: 0,
                accepted: 0,
                rescheduled: 0,
                deadLettered: 0,
                pendingAfterFlush: snapshot.pending
            )
        }
        let records = Array(candidates.prefix {
            $0.event.tenantID == first.event.tenantID && $0.event.deviceID == first.event.deviceID
        })
        let envelope = deterministicEnvelope(records)

        isFlushing = true
        defer { isFlushing = false }
        do {
            let apiKey = try await credentialProvider.apiKey()
            let acknowledgement = try await transport.send(
                envelope: envelope,
                configuration: configuration.transport,
                apiKey: apiKey
            )
            return await apply(acknowledgement, records: records, batchID: envelope.batchID)
        } catch let failure as WardenTransportFailure {
            return await handleTransportFailure(failure, records: records)
        } catch {
            let failure = WardenTransportFailure(
                kind: .network(String(describing: error)),
                retryable: true
            )
            return await handleTransportFailure(failure, records: records)
        }
    }

    public func snapshot() async -> WardenQueueSnapshot { await store.snapshot() }
    public func pendingEvents() async -> [WardenStoredRecord] { await store.pendingEvents() }
    public func deadLetters() async -> [WardenDeadLetter] { await store.deadLetters() }
    public func receipts() async -> [WardenReceipt] { await store.receipts() }

    private func deterministicEnvelope(_ records: [WardenStoredRecord]) -> WardenBatchEnvelope {
        let tenant = records.first?.event.tenantID ?? ""
        let device = records.first?.event.deviceID ?? ""
        let IDs = records.map { $0.event.id }.joined(separator: "\n")
        let batchID = "batch-" + WardenDigest.sha256Hex(Data("\(tenant)\n\(device)\n\(IDs)".utf8))
        return WardenBatchEnvelope(
            batchID: batchID,
            sentAt: records.map(\.enqueuedAt).min() ?? Date(),
            tenantID: records.first?.event.tenantID,
            events: records.map(\.event)
        )
    }

    private func apply(
        _ acknowledgement: WardenBatchAcknowledgement,
        records: [WardenStoredRecord],
        batchID: String
    ) async -> WardenFlushReport {
        let submitted = Set(records.map { $0.event.id })
        let acceptedIDs = Set(acknowledgement.accepted.map(\.eventID))
        let rejectedIDs = Set(acknowledgement.rejected.map(\.eventID))
        guard acknowledgement.batchID == batchID,
              acceptedIDs.isDisjoint(with: rejectedIDs),
              acceptedIDs.union(rejectedIDs) == submitted else {
            return await handleTransportFailure(
                WardenTransportFailure(kind: .invalidAcknowledgement, retryable: true),
                records: records
            )
        }

        let events = Dictionary(uniqueKeysWithValues: records.map { ($0.event.id, $0.event) })
        guard acknowledgement.accepted.allSatisfy({ receipt in
            events[receipt.eventID].map { receiptVerifier.verify(receipt: receipt, event: $0) } ?? false
        }) else {
            return await handleTransportFailure(
                WardenTransportFailure(kind: .invalidAcknowledgement, retryable: true),
                records: records
            )
        }

        var accepted = 0
        var rescheduled = 0
        var deadLettered = 0
        do {
            try await store.acknowledge(acknowledgement.accepted)
            accepted = acknowledgement.accepted.count
        } catch {
            return await report(.deferred, attempted: records.count, message: "Receipt persistence failed.")
        }

        for rejection in acknowledgement.rejected {
            guard let record = records.first(where: { $0.event.id == rejection.eventID }) else { continue }
            if rejection.retryable, record.attemptCount + 1 < configuration.transport.retryPolicy.maxAttempts {
                let delay = configuration.transport.retryPolicy.delay(
                    afterAttempt: record.attemptCount + 1,
                    serverDelay: rejection.retryAfterSeconds
                )
                try? await store.reschedule(
                    eventIDs: [record.event.id],
                    nextAttemptAt: Date().addingTimeInterval(delay),
                    failure: "\(rejection.code): \(rejection.message)"
                )
                rescheduled += 1
            } else {
                try? await store.deadLetter(
                    eventID: record.event.id,
                    code: rejection.code,
                    reason: rejection.message
                )
                deadLettered += 1
            }
        }

        let disposition: WardenFlushDisposition = accepted == records.count
            ? .completed
            : (accepted > 0 || deadLettered > 0 ? .partiallyCompleted : .deferred)
        return await report(
            disposition,
            attempted: records.count,
            accepted: accepted,
            rescheduled: rescheduled,
            deadLettered: deadLettered
        )
    }

    private func handleTransportFailure(
        _ failure: WardenTransportFailure,
        records: [WardenStoredRecord]
    ) async -> WardenFlushReport {
        if !failure.retryable {
            for record in records {
                try? await store.deadLetter(
                    eventID: record.event.id,
                    code: "transport_failure",
                    reason: failure.localizedDescription
                )
            }
            return await report(
                .partiallyCompleted,
                attempted: records.count,
                deadLettered: records.count,
                message: failure.localizedDescription
            )
        }

        var rescheduled = 0
        var deadLettered = 0
        for record in records {
            let nextAttempt = record.attemptCount + 1
            if nextAttempt < configuration.transport.retryPolicy.maxAttempts {
                let delay = configuration.transport.retryPolicy.delay(
                    afterAttempt: nextAttempt,
                    serverDelay: failure.retryAfter
                )
                try? await store.reschedule(
                    eventIDs: [record.event.id],
                    nextAttemptAt: Date().addingTimeInterval(delay),
                    failure: failure.localizedDescription
                )
                rescheduled += 1
            } else {
                try? await store.deadLetter(
                    eventID: record.event.id,
                    code: "retry_exhausted",
                    reason: failure.localizedDescription
                )
                deadLettered += 1
            }
        }
        return await report(
            deadLettered > 0 ? .partiallyCompleted : .deferred,
            attempted: records.count,
            rescheduled: rescheduled,
            deadLettered: deadLettered,
            message: failure.localizedDescription
        )
    }

    private func report(
        _ disposition: WardenFlushDisposition,
        attempted: Int = 0,
        accepted: Int = 0,
        rescheduled: Int = 0,
        deadLettered: Int = 0,
        message: String? = nil
    ) async -> WardenFlushReport {
        let snapshot = await store.snapshot()
        return WardenFlushReport(
            disposition: disposition,
            attempted: attempted,
            accepted: accepted,
            rescheduled: rescheduled,
            deadLettered: deadLettered,
            pendingAfterFlush: snapshot.pending,
            message: message
        )
    }
}
