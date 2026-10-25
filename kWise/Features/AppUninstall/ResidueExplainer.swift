//
// 残留白话解释器 (v2.6)：规则表 + 路径模式 → 确定性白话说明。
// 不调用生成式模型 —— 可解释、可测试（spec §5）。
import Foundation
import AppCatalogCore

enum ResidueExplainer {

    /// 返回一条面向普通用户的白话说明，解释该残留文件是什么、删除后会怎样。
    ///
    /// 确定性规则（无生成式模型）：
    /// 1. 聊天类路径优先（用户最关心的数据安全提示）——只匹配具体的
    ///    聊天数据目录名（`MessageStore` / `ChatStorage` / `MessageArchive`），
    ///    避免任意含 "message" 的目录误触发警告。
    /// 2. `ResidueType` 规则表。
    /// 3. 路径模式补充（Application Support / Logs）。
    /// 4. default 兜底：由 `appName` 生成归属说明。
    ///
    /// - Parameters:
    ///   - residue: 待解释的残留文件。
    ///   - appName: 残留归属的应用名，仅用于 default 兜底文案。
    /// - Returns: 简体中文白话说明，可直接展示在卸载确认列表中。
    static func explain(_ residue: ResidueFile, appName: String) -> String {
        let path = residue.url.path

        // 聊天类路径优先（用户最关心的数据安全提示）。
        let chatMarkers = ["MessageStore", "ChatStorage", "MessageArchive"]
        if residue.type == .appSupport || residue.type == .container,
           chatMarkers.contains(where: { path.localizedCaseInsensitiveContains($0) }) {
            return String(localized: String.LocalizationValue("uninstall.residue.chatData"))
        }

        switch residue.type {
        case .preferences:
            return String(localized: String.LocalizationValue("uninstall.residue.preferences"))
        case .caches:
            return String(localized: String.LocalizationValue("uninstall.residue.caches"))
        case .savedState:
            return String(localized: String.LocalizationValue("uninstall.residue.savedState"))
        case .httpStorage:
            return String(localized: String.LocalizationValue("uninstall.residue.httpStorage"))
        case .launchAgent, .launchDaemon, .startupItem:
            return String(localized: String.LocalizationValue("uninstall.residue.launchItem"))
        case .webKit, .cookie:
            return String(localized: String.LocalizationValue("uninstall.residue.webData"))
        case .groupContainer:
            return String(localized: String.LocalizationValue("uninstall.residue.groupContainer"))
        case .plugin, .prefPane:
            return String(localized: String.LocalizationValue("uninstall.residue.plugin"))
        case .log:
            return String(localized: String.LocalizationValue("uninstall.residue.log"))
        case .appleScript:
            return String(localized: String.LocalizationValue("uninstall.residue.appleScript"))
        default:
            break
        }

        // 路径模式补充（未知 type 或需要更细的解释）。
        if path.contains("Application Support") {
            return String(localized: String.LocalizationValue("uninstall.residue.appSupport"))
        }
        if path.contains("Logs") {
            return String(localized: String.LocalizationValue("uninstall.residue.log"))
        }
        return String(
            format: String(localized: String.LocalizationValue("uninstall.residue.fallback")),
            appName)
    }

    /// 归属推断共享 API：label 反查 zh 映射 → 「这是 XX 的后台助手」。
    /// StartupItemsViewModel 的启动项用途推断与本模块共用此实现。
    ///
    /// 清洗后长度 < 3 的 label 直接返回 `nil`，避免超短字符串（如单字符
    /// 残片）在 bundle ID 包含判断中产生误报。
    ///
    /// - Parameters:
    ///   - label: 启动项 label（如 `com.tencent.xinWeChat.helper`）。
    ///   - mappings: `zh_app_mappings.json` 解码出的映射数组。
    /// - Returns: 命中时的归属提示文案；清洗为空/过短或未命中时为 `nil`。
    static func ownerHint(forLabel label: String, mappings: [ZhAppMapping]) -> String? {
        let cleaned = label
            .replacingOccurrences(of: "com.", with: "")
            .replacingOccurrences(of: "update", with: "")
            .replacingOccurrences(of: "agent", with: "")
            .replacingOccurrences(of: "helper", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 3 else { return nil }
        for mapping in mappings {
            if cleaned.lowercased().contains(
                mapping.bundleID.replacingOccurrences(of: "com.", with: "").lowercased())
                || mapping.bundleID.lowercased().contains(cleaned.lowercased()) {
                return String(
                    format: String(localized: String.LocalizationValue("uninstall.residue.ownerHint")),
                    mapping.displayName)
            }
        }
        return nil
    }
}
