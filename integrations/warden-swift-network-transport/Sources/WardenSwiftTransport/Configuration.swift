import Foundation

public struct WardenRetryPolicy: Sendable, Equatable {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maximumDelay: TimeInterval
    public let jitterFraction: Double

    public init(
        maxAttempts: Int = 5,
        baseDelay: TimeInterval = 1,
        maximumDelay: TimeInterval = 60,
        jitterFraction: Double = 0.20
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = max(0, baseDelay)
        self.maximumDelay = max(self.baseDelay, maximumDelay)
        self.jitterFraction = min(max(0, jitterFraction), 1)
    }

    public func delay(
        afterAttempt attempt: Int,
        serverDelay: TimeInterval? = nil,
        jitterUnit: Double = Double.random(in: 0...1)
    ) -> TimeInterval {
        if let serverDelay {
            return min(maximumDelay, max(0, serverDelay))
        }

        let exponent = max(0, attempt - 1)
        let base = min(maximumDelay, baseDelay * pow(2, Double(exponent)))
        let spread = base * jitterFraction
        let centeredJitter = (min(max(jitterUnit, 0), 1) * 2 - 1) * spread
        return min(maximumDelay, max(0, base + centeredJitter))
    }
}

public struct WardenMetadataPolicy: Sendable, Equatable {
    public let allowedKeys: Set<String>
    public let maximumEntries: Int
    public let maximumKeyLength: Int
    public let maximumValueLength: Int

    public init(
        allowedKeys: Set<String> = [],
        maximumEntries: Int = 32,
        maximumKeyLength: Int = 64,
        maximumValueLength: Int = 512
    ) {
        self.allowedKeys = allowedKeys
        self.maximumEntries = max(0, maximumEntries)
        self.maximumKeyLength = max(1, maximumKeyLength)
        self.maximumValueLength = max(1, maximumValueLength)
    }
}

public enum WardenAuthorityRequirement: Sendable, Equatable {
    case required
    case permitNoneForDevelopment
}


public enum WardenRegistryIdentityRequirement: Sendable, Equatable {
    case required
    case permitMissingForDevelopment
}

public enum WardenEventSignatureRequirement: Sendable, Equatable {
    case required
    case permitUnsignedForDevelopment
}

public enum WardenQueueOverflowPolicy: Sendable, Equatable {
    /// Preserve existing evidence and reject the new event.
    case rejectNewest
    /// Intended only for non-evidentiary telemetry. The removed event becomes a dead letter.
    case deadLetterOldest
}

public enum WardenAcknowledgementMode: Sendable, Equatable {
    /// The server must return a decodable per-event acknowledgement body.
    case signedOrExplicitReceipt
    /// Development compatibility mode: an empty 2xx response acknowledges every event in the request.
    case acceptEmptySuccessResponse
}

public struct WardenTransportConfiguration: Sendable, Equatable {
    public let endpoint: URL?
    public let allowNetwork: Bool
    public let allowInsecureHTTP: Bool
    public let requestTimeout: TimeInterval
    public let maximumBatchSize: Int
    public let headers: [String: String]
    public let acknowledgementMode: WardenAcknowledgementMode
    public let retryPolicy: WardenRetryPolicy

    public init(
        endpoint: URL? = nil,
        allowNetwork: Bool = true,
        allowInsecureHTTP: Bool = false,
        requestTimeout: TimeInterval = 20,
        maximumBatchSize: Int = 50,
        headers: [String: String] = [:],
        acknowledgementMode: WardenAcknowledgementMode = .signedOrExplicitReceipt,
        retryPolicy: WardenRetryPolicy = WardenRetryPolicy()
    ) {
        self.endpoint = endpoint
        self.allowNetwork = allowNetwork
        self.allowInsecureHTTP = allowInsecureHTTP
        self.requestTimeout = max(1, requestTimeout)
        self.maximumBatchSize = max(1, maximumBatchSize)
        self.headers = headers
        self.acknowledgementMode = acknowledgementMode
        self.retryPolicy = retryPolicy
    }
}

public struct WardenConfiguration: Sendable, Equatable {
    public let transport: WardenTransportConfiguration
    public let metadataPolicy: WardenMetadataPolicy
    public let authorityRequirement: WardenAuthorityRequirement
    public let registryIdentityRequirement: WardenRegistryIdentityRequirement
    public let eventSignatureRequirement: WardenEventSignatureRequirement
    public let maximumQueueSize: Int
    public let overflowPolicy: WardenQueueOverflowPolicy
    public let flushAfterEachEvent: Bool
    public let defaultTenantID: String?
    public let defaultActorID: String?
    public let defaultDeviceID: String?
    public let defaultProjectID: String?
    public let defaultAppBundle: String?

    public init(
        transport: WardenTransportConfiguration = WardenTransportConfiguration(),
        metadataPolicy: WardenMetadataPolicy = WardenMetadataPolicy(),
        authorityRequirement: WardenAuthorityRequirement = .required,
        registryIdentityRequirement: WardenRegistryIdentityRequirement = .required,
        eventSignatureRequirement: WardenEventSignatureRequirement = .required,
        maximumQueueSize: Int = 5_000,
        overflowPolicy: WardenQueueOverflowPolicy = .rejectNewest,
        flushAfterEachEvent: Bool = false,
        defaultTenantID: String? = nil,
        defaultActorID: String? = nil,
        defaultDeviceID: String? = nil,
        defaultProjectID: String? = nil,
        defaultAppBundle: String? = nil
    ) {
        self.transport = transport
        self.metadataPolicy = metadataPolicy
        self.authorityRequirement = authorityRequirement
        self.registryIdentityRequirement = registryIdentityRequirement
        self.eventSignatureRequirement = eventSignatureRequirement
        self.maximumQueueSize = max(1, maximumQueueSize)
        self.overflowPolicy = overflowPolicy
        self.flushAfterEachEvent = flushAfterEachEvent
        self.defaultTenantID = defaultTenantID
        self.defaultActorID = defaultActorID
        self.defaultDeviceID = defaultDeviceID
        self.defaultProjectID = defaultProjectID
        self.defaultAppBundle = defaultAppBundle
    }
}

public protocol WardenCredentialProvider: Sendable {
    func apiKey() async throws -> String?
}

public struct WardenNoCredentialProvider: WardenCredentialProvider, Sendable {
    public init() {}
    public func apiKey() async throws -> String? { nil }
}

public struct WardenStaticCredentialProvider: WardenCredentialProvider, Sendable {
    private let value: String?

    public init(_ value: String?) {
        self.value = value
    }

    public func apiKey() async throws -> String? { value }
}

#if canImport(Security)
import Security

public struct WardenKeychainCredentialProvider: WardenCredentialProvider, Sendable {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    public func apiKey() async throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw WardenCredentialError.keychainStatus(status)
        }
        return value
    }
}

public enum WardenCredentialError: Error, Sendable {
    case keychainStatus(OSStatus)
}
#endif
