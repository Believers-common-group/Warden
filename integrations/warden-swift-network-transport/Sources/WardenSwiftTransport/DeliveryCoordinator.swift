import Foundation

public enum WardenDeliveryReason: String, Sendable, Codable, Hashable {
    case manual
    case applicationActivation
    case networkRestored
    case backgroundProcessing
    case eventThreshold
}

public struct WardenDrainReport: Sendable, Equatable {
    public let reason: WardenDeliveryReason
    public let passes: Int
    public let attempted: Int
    public let accepted: Int
    public let rescheduled: Int
    public let deadLettered: Int
    public let pendingAfterDrain: Int
    public let finalDisposition: WardenFlushDisposition
    public let message: String?

    public init(
        reason: WardenDeliveryReason,
        passes: Int,
        attempted: Int,
        accepted: Int,
        rescheduled: Int,
        deadLettered: Int,
        pendingAfterDrain: Int,
        finalDisposition: WardenFlushDisposition,
        message: String? = nil
    ) {
        self.reason = reason
        self.passes = passes
        self.attempted = attempted
        self.accepted = accepted
        self.rescheduled = rescheduled
        self.deadLettered = deadLettered
        self.pendingAfterDrain = pendingAfterDrain
        self.finalDisposition = finalDisposition
        self.message = message
    }
}

/// Coordinates lifecycle- and network-driven delivery without introducing a
/// process-local repeating timer. Each request drains only immediately-ready
/// batches and stops when the queue is empty, deferred, blocked, or the pass
/// limit is reached.
public actor WardenDeliveryCoordinator {
    private let logger: WardenLogger
    private var isDraining = false

    public init(logger: WardenLogger) {
        self.logger = logger
    }

    public func requestFlush(
        reason: WardenDeliveryReason = .manual,
        maximumPasses: Int = 20
    ) async -> WardenDrainReport {
        guard !isDraining else {
            let snapshot = await logger.snapshot()
            return WardenDrainReport(
                reason: reason,
                passes: 0,
                attempted: 0,
                accepted: 0,
                rescheduled: 0,
                deadLettered: 0,
                pendingAfterDrain: snapshot.pending,
                finalDisposition: .alreadyRunning,
                message: "A delivery drain is already running."
            )
        }

        isDraining = true
        defer { isDraining = false }

        let passLimit = max(1, maximumPasses)
        var passes = 0
        var attempted = 0
        var accepted = 0
        var rescheduled = 0
        var deadLettered = 0
        var finalDisposition: WardenFlushDisposition = .noWork
        var finalMessage: String?

        while passes < passLimit {
            let report = await logger.flush()
            passes += 1
            attempted += report.attempted
            accepted += report.accepted
            rescheduled += report.rescheduled
            deadLettered += report.deadLettered
            finalDisposition = report.disposition
            finalMessage = report.message

            switch report.disposition {
            case .completed, .partiallyCompleted:
                if report.pendingAfterFlush == 0 {
                    break
                }
                // Continue only to resolve another batch that is already ready.
                continue
            case .noWork, .deferred, .blocked, .alreadyRunning:
                break
            }
            break
        }

        let snapshot = await logger.snapshot()
        if passes == passLimit, snapshot.pending > 0,
           finalDisposition == .completed || finalDisposition == .partiallyCompleted {
            finalDisposition = .partiallyCompleted
            finalMessage = "The immediate drain pass limit was reached; pending events remain queued."
        }

        return WardenDrainReport(
            reason: reason,
            passes: passes,
            attempted: attempted,
            accepted: accepted,
            rescheduled: rescheduled,
            deadLettered: deadLettered,
            pendingAfterDrain: snapshot.pending,
            finalDisposition: finalDisposition,
            message: finalMessage
        )
    }
}
