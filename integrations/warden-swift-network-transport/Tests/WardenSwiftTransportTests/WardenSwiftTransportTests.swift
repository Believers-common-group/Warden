import XCTest
@testable import WardenSwiftTransport

final class WardenSwiftTransportTests: XCTestCase {
    func testSignedEventIsPersistedWithAllowlistedMetadata() async throws {
        let store = WardenMemoryEventStore()
        let signer = try WardenHMACSHA256Signer(
            key: Data("01234567890123456789012345678901".utf8),
            keyID: "test-key"
        )
        let logger = WardenLogger(
            configuration: WardenConfiguration(
                metadataPolicy: WardenMetadataPolicy(allowedKeys: ["product_id"]),
                defaultTenantID: "tenant",
                defaultDeviceID: "device",
                defaultProjectID: "project"
            ),
            store: store,
            signer: signer
        )
        let result = await logger.log(
            type: .productReceived,
            purpose: "custody",
            authority: WardenAuthority(basis: .contract, reference: "PO-1"),
            metadata: ["product_id": "SKU-1", "password": "redacted"]
        )
        guard case .accepted = result else { return XCTFail("event rejected") }
        let events = await logger.pendingEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].event.metadata, ["product_id": "SKU-1"])
        XCTAssertTrue(events[0].event.hasValidCanonicalHash())
        XCTAssertNotNil(events[0].event.signature)
    }
}
