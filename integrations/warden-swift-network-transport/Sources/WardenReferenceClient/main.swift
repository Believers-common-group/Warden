import Foundation
import WardenSwiftTransport

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

@main
struct WardenReferenceClient {
    static func main() async {
        let environment = ProcessInfo.processInfo.environment
        let endpointString = environment["WARDEN_ENDPOINT"]
            ?? "http://127.0.0.1:8787/v1/warden/batches"
        let receiptSecret = environment["WARDEN_RECEIPT_HMAC_KEY"]
            ?? "development-receipt-secret"
        let receiptKeyID = environment["WARDEN_RECEIPT_KEY_ID"]
            ?? "riveros-receipt-v1"
        let apiKey = environment["WARDEN_API_KEY"]
        let tenantID = environment["WARDEN_TENANT_ID"] ?? "tenant-reference"
        let deviceID = environment["WARDEN_DEVICE_ID"] ?? "device-reference"
        let projectID = environment["WARDEN_PROJECT_ID"] ?? "project-reference"
        let deviceSecret = environment["WARDEN_DEVICE_HMAC_KEY"] ?? "development-device-secret"

        guard let endpoint = URL(string: endpointString) else {
            writeError("Invalid WARDEN_ENDPOINT.")
            exit(2)
        }

        do {
            let verifier = try WardenHMACReceiptVerifier(
                key: Data(receiptSecret.utf8),
                keyID: receiptKeyID
            )
            let configuration = WardenConfiguration(
                transport: WardenTransportConfiguration(
                    endpoint: endpoint,
                    allowInsecureHTTP: endpoint.scheme?.lowercased() == "http",
                    maximumBatchSize: 20,
                    retryPolicy: WardenRetryPolicy(
                        maxAttempts: 3,
                        baseDelay: 0,
                        maximumDelay: 0,
                        jitterFraction: 0
                    )
                ),
                metadataPolicy: WardenMetadataPolicy(
                    allowedKeys: ["warehouse_id", "product_id"]
                ),
                defaultTenantID: tenantID,
                defaultActorID: "reference-actor",
                defaultDeviceID: deviceID,
                defaultProjectID: projectID,
                defaultAppBundle: "org.believerscommon.warden.reference"
            )

            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("warden-reference-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
            let store = try WardenFileEventStore(
                fileURL: temporaryDirectory.appendingPathComponent("event-store.json"),
                protector: WardenUnprotectedPayloadProtector()
            )

            let signer = try WardenHMACSHA256Signer(
                key: Data(deviceSecret.utf8),
                keyID: "reference-device-hmac-v1"
            )
            let logger = WardenLogger(
                configuration: configuration,
                store: store,
                credentialProvider: WardenStaticCredentialProvider(apiKey),
                receiptVerifier: verifier,
                signer: signer
            )
            let coordinator = WardenDeliveryCoordinator(logger: logger)

            let logResult = await logger.log(
                type: .productReceived,
                purpose: "Reference end-to-end custody event",
                authority: WardenAuthority(
                    basis: .contract,
                    reference: "reference-order:PO-0001"
                ),
                policyDecision: .allow,
                retentionClass: "reference-evidence",
                metadata: [
                    "warehouse_id": "WH-REFERENCE",
                    "product_id": "SKU-REFERENCE",
                    "access_token": "removed-by-allowlist"
                ]
            )

            guard case .accepted(let eventID, let sequence) = logResult else {
                writeError("Event was rejected locally: \(String(describing: logResult))")
                exit(3)
            }

            let report = await coordinator.requestFlush(reason: .manual)
            let receipts = await logger.receipts()
            let output: [String: Any] = [
                "eventID": eventID,
                "sequence": sequence,
                "disposition": String(describing: report.finalDisposition),
                "accepted": report.accepted,
                "pending": report.pendingAfterDrain,
                "receiptIDs": receipts.map(\.receiptID)
            ]
            let data = try JSONSerialization.data(
                withJSONObject: output,
                options: [.prettyPrinted, .sortedKeys]
            )
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))

            guard report.accepted == 1,
                  report.pendingAfterDrain == 0,
                  receipts.count == 1 else {
                exit(4)
            }
        } catch {
            writeError("Reference client failed: \(error)")
            exit(5)
        }
    }
    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
