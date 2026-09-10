// kWise/Features/DuplicateFile/DuplicateReportExporter.swift
//
// 重复文件 CSV 报告导出 (v2.6 W1)。
import AppKit
import UniformTypeIdentifiers
import Foundation

enum DuplicateReportExporter {

    /// 生成 CSV 文本：组序号, 类别, 文件路径, 大小, 建议动作。
    static func csv(from groups: [ToolboxGroup]) -> String {
        var lines = ["组序号,类别,建议动作,文件路径,大小(字节)"]
        for (index, group) in groups.enumerated() {
            let action = group.files.first?.isSelected == true ? "删除此份" : "保留"
            for file in group.files {
                let suggested = file.isSelected ? "删除此份" : "保留原件"
                _ = action
                lines.append("\(index + 1),\"\(group.evidenceSummary)\",\"\(suggested)\",\"\(file.url.path)\",\(file.size)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// NSSavePanel 导出；返回保存 URL（用户取消则 nil）。
    @MainActor
    static func export(groups: [ToolboxGroup]) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "重复文件报告.csv"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let csv = csv(from: groups)
        try? csv.data(using: .utf8)?.write(to: url)
        return url
    }
}
