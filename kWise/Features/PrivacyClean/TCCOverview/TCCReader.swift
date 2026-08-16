import Foundation
import SQLite3

public enum TCCReaderError: Error, LocalizedError {
    /// TCC.db file is at the expected path but cannot be opened. Almost
    /// always means Full Disk Access is missing — the OS returns nil/SQLITE_CANTOPEN
    /// for protected files when the process lacks TCC `kTCCServiceAllFiles`.
    case databaseUnreadable
    /// Database opened but a query failed (schema drift, etc.).
    case queryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .databaseUnreadable:
            return "无法读取 TCC 数据库。请在 系统设置 → 隐私与安全 → 完整磁盘访问 中授权 kWise。"
        case .queryFailed(let message):
            return "查询失败：\(message)"
        }
    }
}

/// Reader for the macOS TCC (Transparency, Consent, and Control) database.
///
/// TCC.db lives at `~/Library/Application Support/com.apple.TCC/TCC.db`
/// and is **protected by Full Disk Access** — without FDA the OS returns
/// `SQLITE_CANTOPEN`. We surface that as ``TCCReaderError/databaseUnreadable``
/// rather than guessing, and the view layer (Phase C Task 9) renders a
/// fallback "打开系统设置" CTA per Q8 (FDA-aware primary + fallback).
///
/// - Important: TCC.db schema is **not public** — we tolerate column drift
///   by relying on the most-stable aggregates (`COUNT`, `SUM(CASE...)`, `MAX`)
///   over whatever columns exist in this macOS release. If a future macOS
///   renames the `auth_value` column, ``loadCategories()`` returns an
///   empty list rather than crashing.
/// - SeeAlso: `docs/superpowers/plans/2026-08-09-kwise-v1.5-plan.md` Task 8
@MainActor
public final class TCCReader: ObservableObject {
    @Published public private(set) var categories: [PermissionCategory] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: TCCReaderError?
    @Published public private(set) var lastRefreshedAt: Date?

    /// Path to the TCC database. Tests can inject a custom path via
    /// ``init(tccDBPath:)``; production uses ``defaultDBPath``.
    public let tccDBPath: String

    public init(tccDBPath: String = TCCReader.defaultDBPath) {
        self.tccDBPath = tccDBPath
    }

    public static var defaultDBPath: String {
        let home = NSHomeDirectory()
        return "\(home)/Library/Application Support/com.apple.TCC/TCC.db"
    }

    /// Refresh categories from TCC.db. On error, populates ``lastError``
    /// and leaves ``categories`` empty so the view can render the fallback.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let cats = try await loadCategories()
            categories = cats
            lastError = nil
            lastRefreshedAt = Date()
        } catch let e as TCCReaderError {
            lastError = e
            categories = []
        } catch {
            lastError = .databaseUnreadable
            categories = []
        }
    }

    /// Primary path: open TCC.db read-only with SQLite3 and aggregate the
    /// `access` table by service. Returns friendly `PermissionCategory`
    /// rows. Throws ``TCCReaderError`` on failure.
    private func loadCategories() async throws -> [PermissionCategory] {
        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(tccDBPath, &db, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database = db else {
            sqlite3_close(db)
            throw TCCReaderError.databaseUnreadable
        }
        defer { sqlite3_close(database) }

        // Aggregate by service. The `client IS NOT NULL` filter drops the
        // empty pseudo-rows macOS occasionally leaves in TCC.db.
        let sql = """
            SELECT service,
                   COUNT(*) as total,
                   SUM(CASE WHEN auth_value = 2 THEN 1 ELSE 0 END) as granted,
                   MAX(last_modified_time) as last_modified
            FROM access
            WHERE client IS NOT NULL
            GROUP BY service
            HAVING total > 0
            """

        var statement: OpaquePointer?
        let prepResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepResult == SQLITE_OK, let stmt = statement else {
            let msg = String(cString: sqlite3_errmsg(database))
            sqlite3_finalize(stmt)
            throw TCCReaderError.queryFailed(msg)
        }
        defer { sqlite3_finalize(stmt) }

        var results: [PermissionCategory] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let servicePtr = sqlite3_column_text(stmt, 0)
            let service = servicePtr.map { String(cString: $0) } ?? ""
            let total = Int(sqlite3_column_int(stmt, 1))
            let granted = Int(sqlite3_column_int(stmt, 2))
            let lastModifiedPtr = sqlite3_column_text(stmt, 3)
            let lastModifiedString = lastModifiedPtr.map { String(cString: $0) } ?? ""
            let lastModified = Self.parseTCCDate(lastModifiedString)

            let title = PermissionCategory.fallbackCatalog
                .first(where: { $0.service == service })?.title ?? service
            let cat = PermissionCategory(
                id: service,
                title: title,
                service: service,
                grantedAppCount: granted,
                totalAppCount: total,
                lastUpdatedAt: lastModified
            )
            results.append(cat)
        }
        return results.sorted { lhs, rhs in
            // Display by canonical-catalog order, with unknown services last.
            let lhsOrder = PermissionCategory.fallbackCatalog.firstIndex(where: { $0.service == lhs.service }) ?? Int.max
            let rhsOrder = PermissionCategory.fallbackCatalog.firstIndex(where: { $0.service == rhs.service }) ?? Int.max
            return lhsOrder < rhsOrder
        }
    }

    /// Parse TCC.db's `last_modified_time` text column. macOS 13+ writes
    /// ISO 8601 strings; older formats use locale-dependent variants. We
    /// try a few shapes and return `nil` on parse failure — the row still
    /// surfaces with `lastUpdatedAt == nil`.
    private static func parseTCCDate(_ raw: String) -> Date? {
        let formats = [
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        for fmt in formats {
            df.dateFormat = fmt
            if let d = df.date(from: raw) { return d }
        }
        // ISO 8601 fallback (uses Date.ISO8601 parser).
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: raw) { return d }
        return nil
    }

    /// Fallback categories synthesized when TCC.db is unreadable. Q8 "B" 兜底.
    public func fallbackCategories() -> [PermissionCategory] {
        PermissionCategory.fallbackCatalog
    }
}