// kWise/Tests/MaintenanceGuidanceTests.swift
//
// v2.0 Phase 2 — the maintenance surface must never shell out (App Sandbox
// cannot run /usr/bin/mdutil etc.), and every task must be either
// engine-backed or provide honest Terminal guidance. Source-scan audit,
// same mechanism as ScarewareCopyAuditTests.
import XCTest
@testable import kWise

final class MaintenanceGuidanceTests: XCTestCase {

    private var maintenanceSourceFiles: [String] {
        let base = #filePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .dropLast(3) // Tests/<file>.swift → kWise repo root
            .joined(separator: "/")
        let dir = "/" + base + "/kWise/Features/Maintenance"
        guard let enumerator = FileManager.default.enumerator(atPath: dir) else { return [] }
        return enumerator.compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") }
            .map { dir + "/" + $0 }
    }

    /// Strips Swift comments so the audit reads *code* only.
    ///
    /// The module header legitimately documents the pre-sandbox
    /// implementation ("shelled out via `Process` to `/usr/bin/mdutil`…"),
    /// and a raw `contains("/usr/bin/")` over the whole file flags that
    /// history instead of a real spawn. Dropping `//` line comments and
    /// `/* … */` blocks (nested-aware, string-literal-aware enough for this
    /// module's sources) keeps the audit pointed at executable text.
    private func codeOnly(_ source: String) -> String {
        var out = ""
        var index = source.startIndex
        var inLineComment = false
        var inBlockComment = false
        var blockDepth = 0
        var inString = false

        while index < source.endIndex {
            let ch = source[index]
            let next = source.index(after: index)

            if inLineComment {
                if ch == "\n" { inLineComment = false; out.append(ch) }
                index = next
                continue
            }
            if inBlockComment {
                if ch == "/", next < source.endIndex, source[next] == "*" {
                    blockDepth += 1
                    index = source.index(after: next)
                    continue
                }
                if ch == "*", next < source.endIndex, source[next] == "/" {
                    blockDepth -= 1
                    inBlockComment = blockDepth > 0
                    index = source.index(after: next)
                    continue
                }
                if ch == "\n" { out.append(ch) }
                index = next
                continue
            }
            if inString {
                out.append(ch)
                if ch == "\\" { // keep escaped quotes from closing the literal
                    if next < source.endIndex { out.append(source[next]) }
                    index = source.index(after: next)
                    continue
                }
                if ch == "\"" { inString = false }
                index = next
                continue
            }
            if ch == "/", next < source.endIndex, source[next] == "/" {
                inLineComment = true
                index = source.index(after: next)
                continue
            }
            if ch == "/", next < source.endIndex, source[next] == "*" {
                inBlockComment = true
                blockDepth = 1
                index = source.index(after: next)
                continue
            }
            if ch == "\"" { inString = true }
            out.append(ch)
            index = next
        }
        return out
    }

    /// No `Process` invocations may remain in the maintenance module —
    /// they cannot work sandboxed, so any residual spawn is a lie (C-5).
    func test_noProcessUsageInMaintenanceModule() throws {
        let files = maintenanceSourceFiles
        XCTAssertFalse(files.isEmpty, "Maintenance source directory must be readable from the test bundle")
        for file in files {
            let source = codeOnly(try String(contentsOfFile: file, encoding: .utf8))
            XCTAssertFalse(
                source.contains("Process()"),
                "\(file) must not spawn child processes — sandbox forbids it"
            )
            XCTAssertFalse(
                source.contains("/usr/bin/"),
                "\(file) must not reference CLI binaries — guidance instead"
            )
        }
    }

    /// Every guidance task carries a Terminal command; every engine-backed
    /// task carries none.
    func test_everyTaskEitherGuidanceWithCommandOrEngineBacked() {
        for task in MaintenanceTask.allCases {
            if task.isEngineBacked {
                XCTAssertNil(task.terminalCommand,
                             "\(task) is engine-backed and must not advertise a Terminal command")
            } else {
                let command = try? XCTUnwrap(task.terminalCommand,
                                             "\(task) needs a Terminal command for guidance")
                if let command {
                    XCTAssertFalse(command.isEmpty)
                    XCTAssertTrue(command.hasPrefix("/") || command.contains("sudo"),
                                  "\(task) command should be a concrete Terminal invocation")
                }
                _ = command
            }
        }
    }

    /// Engine backing is restricted to paths inside the user's granted
    /// home scope — never system locations.
    func test_engineBackedTasksAreUserScoped() {
        for task in MaintenanceTask.allCases where task.isEngineBacked {
            XCTAssertNotEqual(task, .spotlightRebuild)
            XCTAssertNotEqual(task, .dnsFlush)
        }
    }
}

@MainActor
final class MaintenanceViewModelTests: XCTestCase {

    func testGuidanceTaskDoesNotPretendToRun() async {
        let vm = MaintenanceViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)
        ))
        await vm.execute(.dnsFlush)
        XCTAssertTrue(vm.results[MaintenanceTask.dnsFlush.id]?.contains("终端") == true,
                      "Guidance tasks must say they need Terminal, never claim success")
    }

    func testCopyCommandWritesPasteboard() {
        let vm = MaintenanceViewModel()
        vm.copyCommand(for: .spotlightRebuild)
        XCTAssertTrue(vm.copiedCommands.contains(MaintenanceTask.spotlightRebuild.id))
        let board = NSPasteboard.general
        let content = board.string(forType: .string)
        XCTAssertEqual(content, MaintenanceTask.spotlightRebuild.terminalCommand)
    }
}
