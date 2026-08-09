import Foundation
import SQLite3

/// Friendly description for one TCC category (e.g. Camera, Full Disk Access).
///
/// Built by ``TCCReader`` from TCC.db rows; falls back to a synthesized
/// stub when the database can't be opened (no Full Disk Access granted),
/// per Q8 of the v1.5 grill-me convergence (FDA-aware primary + fallback).
///
/// - SeeAlso: `docs/superpowers/plans/2026-08-09-kwise-v1.5-plan.md` Task 8
public struct PermissionCategory: Identifiable, Hashable, Sendable {
    /// TCC service identifier (e.g. "kTCCServiceCamera"). Stable across runs.
    public let id: String
    /// User-facing title in 中文 (e.g. "摄像头").
    public let title: String
    /// Same as `id`; kept separate so callers can pass it to system APIs.
    public let service: String
    /// Number of apps with `auth_value = 2` (allowed).
    public let grantedAppCount: Int
    /// Number of distinct apps that requested access in TCC.db.
    public let totalAppCount: Int
    /// Most recent access-modification timestamp from TCC.db.
    public let lastUpdatedAt: Date?

    public init(id: String,
                title: String,
                service: String,
                grantedAppCount: Int,
                totalAppCount: Int,
                lastUpdatedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.service = service
        self.grantedAppCount = grantedAppCount
        self.totalAppCount = totalAppCount
        self.lastUpdatedAt = lastUpdatedAt
    }

    /// Whether the row was synthesized as a fallback (FDA not granted).
    public var isFallback: Bool {
        grantedAppCount == 0 && totalAppCount == 0 && lastUpdatedAt == nil
    }

    /// One-line summary for the overview card.
    public var friendlySummary: String {
        if isFallback { return "需要完整磁盘访问" }
        if totalAppCount == 0 { return "无应用申请" }
        return "\(grantedAppCount) / \(totalAppCount) 应用已授权"
    }
}

extension PermissionCategory {
    /// Canonical catalog of TCC services surfaced in the privacy overview.
    /// Order is the display order in the grid. Fallback uses these titles.
    public static let fallbackCatalog: [PermissionCategory] = [
        .init(id: "kTCCServiceAccessibility",                 title: "辅助功能",        service: "kTCCServiceAccessibility"),
        .init(id: "kTCCServiceAllFiles",                      title: "完整磁盘访问",     service: "kTCCServiceAllFiles"),
        .init(id: "kTCCServiceScreenCapture",                 title: "屏幕录制",        service: "kTCCServiceScreenCapture"),
        .init(id: "kTCCServiceCamera",                        title: "摄像头",          service: "kTCCServiceCamera"),
        .init(id: "kTCCServiceMicrophone",                    title: "麦克风",          service: "kTCCServiceMicrophone"),
        .init(id: "kTCCServiceLocation",                      title: "位置",            service: "kTCCServiceLocation"),
        .init(id: "kTCCServicePhotos",                        title: "照片",            service: "kTCCServicePhotos"),
        .init(id: "kTCCServiceAddressBook",                   title: "通讯录",          service: "kTCCServiceAddressBook"),
        .init(id: "kTCCServiceCalendar",                      title: "日历",            service: "kTCCServiceCalendar"),
        .init(id: "kTCCServiceReminders",                     title: "提醒事项",        service: "kTCCServiceReminders"),
        .init(id: "kTCCServiceBluetooth",                     title: "蓝牙",            service: "kTCCServiceBluetooth"),
        .init(id: "kTCCServiceSystemPolicyDesktopFolder",     title: "文件和文件夹",     service: "kTCCServiceSystemPolicyDesktopFolder"),
    ]
}