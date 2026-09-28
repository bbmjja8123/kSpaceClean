// kWise/Features/Attribution/PathGlobMatcher.swift
//
// 语料 glob 的纯函数匹配器。语义刻意小而明确（spec §4.4 语料只用到这三种）：
//   `~`   → home 前缀（注入，不读 NSHomeDirectory）
//   `**`  → 任意层（含 0 层）
//   `*`   → 单段内任意字符（不跨 '/'）
// 匹配大小写不敏感 —— macOS 默认文件系统如此。
import Foundation

enum PathGlobMatcher {

    static func expandTilde(_ glob: String, home: String) -> String {
        guard glob == "~" || glob.hasPrefix("~/") else { return glob }
        return home + glob.dropFirst(1)
    }

    static func matches(path: String, glob: String, home: String) -> Bool {
        let expanded = expandTilde(glob, home: home)
        let pathSegments = path.lowercased().split(separator: "/").map(String.init)
        let globSegments = expanded.lowercased().split(separator: "/").map(String.init)
        return matchSegments(path: pathSegments, pattern: globSegments)
    }

    private static func matchSegments(path: [String], pattern: [String]) -> Bool {
        guard let head = pattern.first else { return path.isEmpty }
        if head == "**" {
            // `**` 吃 0..n 段。
            for take in 0...path.count {
                if matchSegments(path: Array(path.dropFirst(take)), pattern: Array(pattern.dropFirst())) {
                    return true
                }
            }
            return false
        }
        guard let first = path.first, matchSegment(pattern: head[...], string: first[...]) else { return false }
        return matchSegments(path: Array(path.dropFirst()), pattern: Array(pattern.dropFirst()))
    }

    /// 单段通配（`*` 不跨 '/'）：经典回溯。
    private static func matchSegment(pattern: Substring, string: Substring) -> Bool {
        if pattern.isEmpty { return string.isEmpty }
        if pattern.first == "*" {
            for drop in 0...string.count {
                if matchSegment(pattern: pattern.dropFirst(), string: string.dropFirst(drop)) {
                    return true
                }
            }
            return false
        }
        guard let p = pattern.first, let s = string.first, p == s else { return false }
        return matchSegment(pattern: pattern.dropFirst(), string: string.dropFirst())
    }
}
