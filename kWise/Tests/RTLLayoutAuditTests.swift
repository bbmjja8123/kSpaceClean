// kWise/Tests/RTLLayoutAuditTests.swift
//
// 阿语 RTL 硬门槛：源码不得硬编码 .left/.right 对齐（leading/trailing
// 自动镜像）。审计 grep 全 Features/ 与 App/。加入 12 语本地化（含 ar）
// 后，任何新增的固定 left/right 对齐都会在阿语界面下错边，因此在测试里
// 钉住，而不是依赖人工 review。
import XCTest
import Foundation

final class RTLLayoutAuditTests: XCTestCase {

    /// Banned hardcoded direction APIs. `leading`/`trailing`/natural
    /// alignment mirror automatically under RTL; these do not.
    private static let bannedPatterns = [
        ".alignment: .left", ".alignment: .right",
        "textAlignment = .left", "textAlignment = .right",
        "multilineTextAlignment(.left)", "multilineTextAlignment(.right)",
        "multilineTextAlignment: .left", "multilineTextAlignment: .right",
    ]

    private func auditRoots() -> [URL] {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent() // Tests/
        return [tests.appendingPathComponent("../Features"),
                tests.appendingPathComponent("../App")]
    }

    func testNoHardcodedLeftRightAlignment() throws {
        var violations: [String] = []
        for root in auditRoots() {
            guard FileManager.default.fileExists(atPath: root.path) else {
                throw NSError(domain: "RTLLayoutAuditTests", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "missing \(root.path)"])
            }
            let enumerator = FileManager.default.enumerator(at: root,
                                                            includingPropertiesForKeys: nil)
            for case let file as URL in enumerator!
            where file.pathExtension == "swift" {
                let src = try String(contentsOf: file, encoding: .utf8)
                for banned in Self.bannedPatterns where src.contains(banned) {
                    violations.append("\(file.lastPathComponent): \(banned)")
                }
            }
        }
        XCTAssertTrue(violations.isEmpty,
                      "硬编码 left/right 对齐（RTL 违约），改用 leading/trailing 或自然方向 API：\n"
                        + violations.sorted().joined(separator: "\n"))
    }
}
