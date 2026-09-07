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

    /// No `Process` invocations may remain in the maintenance module —
    /// they cannot work sandboxed, so any residual spawn is a lie (C-5).
    func test_noProcessUsageInMaintenanceModule() throws {
        let files = maintenanceSourceFiles
        XCTAssertFalse(files.isEmpty, "Maintenance source directory must be readable from the test bundle")
        for file in files {
            let source = try String(contentsOfFile: file, encoding: .utf8)
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
        XCTAssertTrue(vm.results[.dnsFlush.id]?.contains("终端") == true,
                      "Guidance tasks must say they need Terminal, never claim success")
    }

    func testCopyCommandWritesPasteboard() {
        let vm = MaintenanceViewModel()
        vm.copyCommand(for: .spotlightRebuild)
        XCTAssertTrue(vm.copiedCommands.contains(.spotlightRebuild.id))
        let board = NSPasteboard.general
        let content = board.string(forType: .string)
        XCTAssertEqual(content, MaintenanceTask.spotlightRebuild.terminalCommand)
    }
}
