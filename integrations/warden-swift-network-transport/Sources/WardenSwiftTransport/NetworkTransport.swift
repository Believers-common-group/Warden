import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct WardenTransportFailure: Error, Sendable, Equatable, LocalizedError {
    public enum Kind: Sendable, Equatable {
        case missingEndpoint
        case insecureEndpoint
        case encoding
        case invalidResponse
        case invalidAcknowledgement
        case invalidIdentity
        case httpStatus(Int)
        case credential(String)
        case network(String)
    }

    public let kind: Kind
    public let retryable: Bool
    public let retryAfter: TimeInterval?

    public init(kind: Kind, retryable: Bool, retryAfter: TimeInterval? = nil) {
        self.kind = kind
        self.retryable = retryable
        self.retryAfter = retryAfter
    }

    public var errorDescription: String? {
        switch kind {
        case .missingEndpoint:
            return "The Warden ingestion endpoint is not configured."
        case .insecureEndpoint:
            return "The Warden ingestion endpoint violates the HTTPS policy."
        case .encoding:
            return "The Warden batch could not be encoded."
        case .invalidResponse:
            return "The Warden service returned a non-HTTP response."
        case .invalidAcknowledgement:
            return "The Warden service did not return a valid per-event acknowledgement."
        case .invalidIdentity:
            return "The Warden batch contains inconsistent tenant or device identity."
        case .httpStatus(let status):
            return "The Warden service returned HTTP \(status)."
        case .credential(let message):
            return "The Warden credential provider failed: \(message)"
        case .network(let message):
            return "The Warden network request failed: \(message)"
        }
    }
}

public protocol WardenBatchTransport: Sendable {
    func send(
        envelope: WardenBatchEnvelope,
        configuration: WardenTransportConfiguration,
        apiKey: String?
    ) async throws -> WardenBatchAcknowledgement
}

public final class URLSessionWardenBatchTransport: WardenBatchTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 2
#if !os(Linux)
        configuration.waitsForConnectivity = true
#endif
        self.session = URLSession(configuration: configuration)
    }

    public func send(
        envelope: WardenBatchEnvelope,
        configuration: WardenTransportConfiguration,
        apiKey: String?
    ) async throws -> WardenBatchAcknowledgement {
        guard let endpoint = configuration.endpoint else {
            throw WardenTransportFailure(kind: .missingEndpoint, retryable: false)
        }

        guard let scheme = endpoint.scheme?.lowercased(),
              scheme == "https" || (configuration.allowInsecureHTTP && scheme == "http") else {
            throw WardenTransportFailure(kind: .insecureEndpoint, retryable: false)
        }

        let eventTenantIDs = Set(envelope.events.compactMap(\.tenantID))
        let eventDeviceIDs = Set(envelope.events.compactMap(\.deviceID))
        if eventTenantIDs.count > 1 || eventDeviceIDs.count > 1 {
            throw WardenTransportFailure(kind: .invalidIdentity, retryable: false)
        }
        if let envelopeTenantID = envelope.tenantID,
           let eventTenantID = eventTenantIDs.first,
           envelopeTenantID != eventTenantID {
            throw WardenTransportFailure(kind: .invalidIdentity, retryable: false)
        }

        var request = URLRequest(
            url: endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: configuration.requestTimeout
        )
        request.httpMethod = "POST"
        for (name, value) in configuration.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        // Protocol-critical headers are set after custom headers so an integration
        // cannot accidentally weaken content typing or idempotency semantics.
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(envelope.batchID, forHTTPHeaderField: "Idempotency-Key")
        request.setValue(envelope.batchID, forHTTPHeaderField: "X-Warden-Batch-ID")
        request.setValue(String(envelope.events.count), forHTTPHeaderField: "X-Warden-Event-Count")
        if let tenantID = envelope.tenantID ?? eventTenantIDs.first, !tenantID.isEmpty {
            request.setValue(tenantID, forHTTPHeaderField: "X-Warden-Tenant-ID")
        }
        if let deviceID = eventDeviceIDs.first, !deviceID.isEmpty {
            request.setValue(deviceID, forHTTPHeaderField: "X-Warden-Device-ID")
        }
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }

        do {
            request.httpBody = try WardenCanonicalJSON.encoder().encode(envelope)
        } catch {
            throw WardenTransportFailure(kind: .encoding, retryable: false)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw WardenTransportFailure(kind: .invalidResponse, retryable: true)
            }

            guard 200...299 ~= http.statusCode else {
                let retryable = Self.isRetryable(statusCode: http.statusCode)
                throw WardenTransportFailure(
                    kind: .httpStatus(http.statusCode),
                    retryable: retryable,
                    retryAfter: Self.retryAfter(from: http)
                )
            }

            if data.isEmpty,
               configuration.acknowledgementMode == .acceptEmptySuccessResponse {
                let now = Date()
                return WardenBatchAcknowledgement(
                    batchID: envelope.batchID,
                    accepted: envelope.events.map {
                        WardenReceipt(
                            eventID: $0.id,
                            receiptID: "transport-\(envelope.batchID)-\($0.id)",
                            recordedAt: now
                        )
                    },
                    rejected: []
                )
            }

            guard let acknowledgement = try? WardenCanonicalJSON.decoder().decode(
                WardenBatchAcknowledgement.self,
                from: data
            ), acknowledgement.batchID == envelope.batchID else {
                throw WardenTransportFailure(
                    kind: .invalidAcknowledgement,
                    retryable: true
                )
            }

            return acknowledgement
        } catch let failure as WardenTransportFailure {
            throw failure
        } catch {
            throw WardenTransportFailure(
                kind: .network(String(describing: error)),
                retryable: true
            )
        }
    }

    private static func isRetryable(statusCode: Int) -> Bool {
        statusCode == 408
            || statusCode == 425
            || statusCode == 429
            || 500...599 ~= statusCode
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(value) else {
            return nil
        }
        return max(0, seconds)
    }
}
