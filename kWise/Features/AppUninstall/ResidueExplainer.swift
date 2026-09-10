//
// 残留白话解释器 (v2.6)：规则表 + 路径模式 → 确定性白话说明。
// 不调用生成式模型 —— 可解释、可测试（spec §5）。
import Foundation
import AppCatalogCore

enum ResidueExplainer {

    static func explain(_ residue: ResidueFile, appName: String) -> String {
        let path = residue.url.path

        // 聊天类路径优先（用户最关心的数据安全提示）。
        let chatMarkers = ["Message", "Chat", "聊天", "WeChat", "MessageStore"]
        if residue.type == .appSupport || residue.type == .container,
           chatMarkers.contains(where: { path.localizedCaseInsensitiveContains($0) }) {
            return "聊天记录数据，删除后聊天图片与消息不再显示"
        }

        switch residue.type {
        case .preferences:
            return "应用的偏好设置，删除后 App 恢复首次启动的默认配置"
        case .caches:
            return "缓存文件，删除后 App 会自动重建"
        case .savedState:
            return "窗口状态记录，删除后无影响"
        case .httpStorage:
            return "网络缓存数据，删除后 App 重新登录可能需要"
        case .launchAgent, .launchDaemon, .startupItem:
            return "开机自启动配置，删除后 App 不再自动启动"
        case .webKit, .cookie:
            return "网页数据（Cookie/本地存储），清理后将退出相关网站的登录"
        case .groupContainer:
            return "应用组共享数据，可能被同厂商多个应用使用"
        case .plugin, .prefPane:
            return "应用插件或系统偏好面板（支撑文件）"
        case .log:
            return "日志文件，通常可安全删除"
        default:
            break
        }

        // 路径模式补充（未知 type 或需要更细的解释）。
        if path.contains("Application Support") {
            return "应用支撑数据目录"
        }
        if path.contains("Logs") {
            return "日志文件，通常可安全删除"
        }
        return "应用的支撑文件（由「\(appName)」创建）"
    }

    /// 归属推断共享 API：label 反查 zh 映射 → 「这是 XX 的后台助手」。
    /// 与 StartupItemsViewModel.inferUsage 保持同一规则（后续迁移点）。
    static func ownerHint(forLabel label: String, mappings: [ZhAppMapping]) -> String? {
        let cleaned = label
            .replacingOccurrences(of: "com.", with: "")
            .replacingOccurrences(of: "update", with: "")
            .replacingOccurrences(of: "agent", with: "")
            .replacingOccurrences(of: "helper", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        for mapping in mappings {
            if cleaned.lowercased().contains(
                mapping.bundleID.replacingOccurrences(of: "com.", with: "").lowercased())
                || mapping.bundleID.lowercased().contains(cleaned.lowercased()) {
                return "这是「\(mapping.displayName)」的后台助手"
            }
        }
        return nil
    }
}
