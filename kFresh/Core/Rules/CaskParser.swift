import Foundation

/// Errors raised by `CaskParser` when a cask ruby source cannot be turned into a `KFreshBundleRule`.
public enum CaskParserError: Error {
    /// The parser could not derive a bundle ID from the cask name or any well-known map.
    case missingBundleID
    /// The ruby source string did not contain a recognizable `cask "..." do ... end` block.
    case malformedInput
}

/// Heuristic parser for Homebrew Cask ruby DSL fragments.
///
/// The parser extracts three signals from a cask:
/// 1. `name "..."` — the human-readable app name.
/// 2. `app "....app"` — the .app filename inside the cask.
/// 3. `zap trash: [ ... ]` — the list of residue paths.
///
/// The bundle ID is inferred from a small known-cask map and falls back to
/// `com.example.<lowercased-name>` for unknown apps. The fallback is intentionally
/// lossy; `BundleRuleStore` will refine it once the cask ruby source is parsed
/// against a real `Info.plist` in a later task.
public enum CaskParser {
    /// Parse a single Homebrew Cask ruby DSL string into a `KFreshBundleRule`.
    ///
    /// - Parameters:
    ///   - rubySource: The raw cask ruby DSL text (typically downloaded from
    ///     `https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/<token[0]>/<token>.rb`).
    ///   - caskName: The cask token (e.g. `visual-studio-code`).
    /// - Returns: A `KFreshBundleRule` populated from the cask metadata.
    /// - Throws: `CaskParserError.malformedInput` if the source has no `name` and the cask name is empty.
    public static func parse(_ rubySource: String, caskName: String) throws -> KFreshBundleRule {
        let name = extract(rubySource, pattern: #"name\s+"([^"]+)""#) ?? caskName.capitalized
        let appFilename = extract(rubySource, pattern: #"app\s+"([^"]+\.app)""#) ?? "\(name).app"
        let bundleID = inferBundleID(caskName: caskName, appName: name, appFilename: appFilename)

        let trashPaths = extractArray(rubySource, key: "trash")
        let userPaths = trashPaths.filter { $0.hasPrefix("~/") }
        let systemPaths = trashPaths.filter { !$0.hasPrefix("~/") }

        return KFreshBundleRule(
            bundleID: bundleID,
            appName: name,
            residuePaths: userPaths,
            systemLevelPaths: systemPaths,
            zapStanzas: [rubySource],
            confidence: 0.95,
            source: "homebrew-cask"
        )
    }

    /// Run `pattern` once over `source` and return the first capture group, if any.
    private static func extract(_ source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[range])
    }

    /// Extract every `"..."` literal inside `key: [ ... ]` (e.g. `trash: ["a", "b"]`).
    /// `(?s)` enables single-line mode so `.` matches newlines, letting the array
    /// body span multiple lines (the typical Homebrew Cask formatting).
    private static func extractArray(_ source: String, key: String) -> [String] {
        let pattern = "(?s)\(key):\\s*\\[(.*?)\\]"
        guard let body = extract(source, pattern: pattern) else { return [] }
        let regex = try? NSRegularExpression(pattern: #""([^"]+)""#)
        guard let regex = regex else { return [] }
        let range = NSRange(body.startIndex..., in: body)
        return regex.matches(in: body, range: range).compactMap {
            Range($0.range(at: 1), in: body).map { String(body[$0]) }
        }
    }

    /// Infer the bundle ID for a known cask; fall back to `com.example.<lowercased-cask-name>`.
    ///
    /// The hardcoded map covers the most-installed macOS apps; everything else is intentionally
    /// a placeholder so consumers can detect a low-confidence heuristic and refine later.
    private static func inferBundleID(caskName: String, appName: String, appFilename: String) -> String {
        let known: [String: String] = [
            "visual-studio-code": "com.microsoft.VSCode",
            "iterm2": "com.googlecode.iterm2",
            "google-chrome": "com.google.Chrome",
            "firefox": "org.mozilla.firefox",
            "slack": "com.tinyspeck.chatlyio",
            "discord": "com.hnc.Discord",
            "notion": "notion.id",
            "figma": "com.figma.Desktop",
            "postman": "com.postmanlabs.mac",
            "spotify": "com.spotify.client",
        ]
        return known[caskName] ?? "com.example.\(caskName.replacingOccurrences(of: "-", with: "."))"
    }
}