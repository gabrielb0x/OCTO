import Foundation

/// Space the ChatGPT account uses for the files of its chats
/// (`GET /files/library/storage/usage`): what ChatGPT keeps on its side, next to what OCTO
/// keeps on the device.
public struct AccountFileStorage: Codable, Equatable, Sendable {
    /// A slice of the storage: a kind of file, or where it came from.
    public struct Bucket: Codable, Equatable, Sendable, Identifiable {
        /// Raw key such as "image", "text", "other", "uploaded" or "generated".
        public var key: String
        public var bytes: Int64
        /// Number of files, when the account counts them.
        public var count: Int?

        public var id: String { key }

        public init(key: String, bytes: Int64, count: Int? = nil) {
            self.key = key
            self.bytes = bytes
            self.count = count
        }
    }

    public var usedBytes: Int64
    public var allowedBytes: Int64?
    public var remainingBytes: Int64?
    public var isOverLimit: Bool
    public var byFileType: [Bucket]
    public var bySource: [Bucket]

    public init(
        usedBytes: Int64,
        allowedBytes: Int64? = nil,
        remainingBytes: Int64? = nil,
        isOverLimit: Bool = false,
        byFileType: [Bucket] = [],
        bySource: [Bucket] = []
    ) {
        self.usedBytes = usedBytes
        self.allowedBytes = allowedBytes
        self.remainingBytes = remainingBytes
        self.isOverLimit = isOverLimit
        self.byFileType = byFileType
        self.bySource = bySource
    }

    /// How full the account's storage is, between 0 and 1. Nil when the account reports no limit.
    public var usedFraction: Double? {
        guard let allowedBytes, allowedBytes > 0 else { return nil }
        return min(Double(usedBytes) / Double(allowedBytes), 1)
    }

    public static func parse(_ data: Data) -> AccountFileStorage? {
        guard let object = JSONValue.object(data), let used = bytes(object["used_bytes"]) else { return nil }
        return AccountFileStorage(
            usedBytes: used,
            allowedBytes: bytes(object["allowed_bytes"]),
            remainingBytes: bytes(object["remaining_bytes"]),
            isOverLimit: JSONValue.bool(object["is_over_limit"]) ?? false,
            byFileType: buckets(object["breakdown_by_file_type"], key: "file_type"),
            bySource: buckets(object["breakdown_by_source"], key: "source")
        )
    }

    static func buckets(_ value: Any?, key: String) -> [Bucket] {
        (value as? [[String: Any]] ?? []).compactMap { entry in
            guard let name = JSONValue.string(entry[key]), !name.isEmpty,
                  let used = bytes(entry["used_bytes"]), used > 0
            else { return nil }
            return Bucket(key: name, bytes: used, count: JSONValue.int(entry["count"]))
        }
        .sorted { $0.bytes > $1.bytes }
    }

    static func bytes(_ value: Any?) -> Int64? {
        JSONValue.int(value).map(Int64.init)
    }
}
