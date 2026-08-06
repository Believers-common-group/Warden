#if os(iOS) && canImport(BackgroundTasks)
import BackgroundTasks
import Foundation

/// Thin iOS adapter around `BGProcessingTask`. The host application must add
/// the identifier to `BGTaskSchedulerPermittedIdentifiers` and call `register()`
/// during application launch.
public final class WardenBackgroundDelivery: @unchecked Sendable {
    public let taskIdentifier: String
    private let coordinator: WardenDeliveryCoordinator
    private let maximumPasses: Int

    public init(
        taskIdentifier: String,
        coordinator: WardenDeliveryCoordinator,
        maximumPasses: Int = 20
    ) {
        self.taskIdentifier = taskIdentifier
        self.coordinator = coordinator
        self.maximumPasses = max(1, maximumPasses)
    }

    @discardableResult
    public func register() -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self, let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(processingTask)
        }
    }

    public func schedule(
        earliestBeginDate: Date? = nil,
        requiresExternalPower: Bool = false
    ) throws {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = earliestBeginDate
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = requiresExternalPower
        try BGTaskScheduler.shared.submit(request)
    }

    public func cancelPendingRequest() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    private func handle(_ task: BGProcessingTask) {
        let operation = Task { [coordinator, maximumPasses] in
            await coordinator.requestFlush(
                reason: .backgroundProcessing,
                maximumPasses: maximumPasses
            )
        }

        task.expirationHandler = {
            operation.cancel()
        }

        Task {
            let report = await operation.value
            let success = !Task.isCancelled
                && report.finalDisposition != .blocked
                && report.finalDisposition != .alreadyRunning
            task.setTaskCompleted(success: success)
        }
    }
}
#endif
