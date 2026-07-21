import Foundation

public struct WardenMetadataSanitizer: Sendable {
    public init() {}

    public func sanitize(
        _ metadata: [String: String],
        policy: WardenMetadataPolicy
    ) -> [String: String] {
        guard !policy.allowedKeys.isEmpty, policy.maximumEntries > 0 else {
            return [:]
        }

        var output: [String: String] = [:]
        output.reserveCapacity(min(metadata.count, policy.maximumEntries))

        for key in metadata.keys.sorted() {
            guard output.count < policy.maximumEntries,
                  policy.allowedKeys.contains(key),
                  key.count <= policy.maximumKeyLength,
                  let value = metadata[key],
                  value.count <= policy.maximumValueLength else {
                continue
            }
            output[key] = value
        }

        return output
    }
}
