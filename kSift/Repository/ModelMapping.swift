import Foundation
import UniformTypeIdentifiers

/// Pure value-mapping helpers shared by the Core Data repository and its tests.
///
/// Every function here is side-effect free: given a `FileItem` / `DuplicateGroup`
/// field it returns the stored representation (or back), so the sentinel and
/// encode/decode rules are verifiable in the SwiftPM harness where Core Data
/// itself cannot run.
public enum ModelMapping {

    // MARK: - FileItem scalar fields

    /// `nil` → 0. APFS inodes start at 1, so 0 is a safe "absent" sentinel.
    public static func inodeValue(_ inode: UInt64?) -> Int64 {
        Int64(inode ?? 0)
    }

    public static func inodeFromStored(_ stored: Int64) -> UInt64? {
        stored == 0 ? nil : UInt64(stored)
    }

    /// `nil` → -1. 0 is a legitimate physical size (empty files), so -1 is the sentinel.
    public static func physicalSizeValue(_ size: Int64?) -> Int64 {
        size ?? -1
    }

    public static func physicalSizeFromStored(_ stored: Int64) -> Int64? {
        stored < 0 ? nil : stored
    }

    public static func fileTypeIdentifier(_ type: UTType?) -> String? {
        type?.identifier
    }

    public static func fileTypeFromIdentifier(_ identifier: String?) -> UTType? {
        identifier.flatMap(UTType.init)
    }

    // MARK: - DuplicateGroup similarity

    /// `nil` → -1. Similarity lives in 0...1, so -1 means "unknown".
    public static func similarityValue(_ similarity: Double?) -> Double {
        similarity ?? -1
    }

    public static func similarityFromStored(_ stored: Double) -> Double? {
        stored < 0 ? nil : stored
    }

    // MARK: - CategoryEvidence JSON

    /// Encodes evidence to a JSON blob for the `evidenceData` attribute.
    /// Returns nil when the value cannot be encoded (should not happen in practice).
    public static func encodeEvidence(_ evidence: CategoryEvidence) -> Data? {
        try? JSONEncoder().encode(evidence)
    }

    /// Decodes a stored evidence blob. Returns nil when absent or malformed —
    /// callers fall back to `fallbackEvidence` for legacy rows.
    public static func decodeEvidence(_ data: Data?) -> CategoryEvidence? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(CategoryEvidence.self, from: data)
    }
}
