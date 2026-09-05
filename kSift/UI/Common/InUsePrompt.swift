import SwiftUI

/// Shared presentation helper for the pre-cleanup in-use warning. The
/// alert wiring lives in each cleanup surface (ResultView,
/// GroupDetailView, LargeFilesListView) but the copy stays consistent.
enum InUsePrompt {
    /// Maximum file names listed inline before an "+N more" collapse.
    private static let maxNames = 5

    static func title(_ report: InUseReport) -> String {
        if !report.inUse.isEmpty {
            return NSLocalizedString("Some files are in use", comment: "In-use warning title")
        }
        return NSLocalizedString("Check for open files", comment: "In-use warning title (heuristics only)")
    }

    static func message(_ report: InUseReport) -> String {
        var lines: [String] = []
        let heldFiles = report.inUse.values.map(\.file).sorted { $0.url.path < $1.url.path }
        if !heldFiles.isEmpty {
            lines.append(NSLocalizedString(
                "These files are currently open in other apps:",
                comment: "In-use warning intro"
            ))
            lines.append(contentsOf: nameList(heldFiles.map { $0.url.lastPathComponent }))
        }
        if !report.likelyInUse.isEmpty {
            lines.append(NSLocalizedString(
                "These files were modified moments ago and may be in use:",
                comment: "Likely-in-use warning intro"
            ))
            lines.append(contentsOf: nameList(report.likelyInUse.map { $0.url.lastPathComponent }))
        }
        if report.checkUnavailable {
            lines.append(NSLocalizedString(
                "The open-file check could not run in this environment, so the list above is heuristic only.",
                comment: "In-use check unavailable notice"
            ))
        }
        return lines.joined(separator: "\n")
    }

    /// The files the "Skip in-use files" action removes from the batch:
    /// only files with real open descriptors, never heuristic-only hits.
    static func filesToSkip(_ report: InUseReport) -> [URL] {
        report.inUse.values.map { $0.file.url }
    }

    private static func nameList(_ names: [String]) -> [String] {
        if names.count > maxNames {
            let shown = names.prefix(maxNames).map { "• \($0)" }
            return shown + [String(
                format: NSLocalizedString("…and %lld more", comment: "In-use list overflow"),
                names.count - maxNames
            )]
        }
        return names.map { "• \($0)" }
    }
}
