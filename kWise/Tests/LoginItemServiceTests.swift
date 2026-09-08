// kWise/Tests/LoginItemServiceTests.swift
//
// v2.0 Phase 1 — SMAppService-backed login item with surfaced errors.
import XCTest
import ServiceManagement
@testable import kWise

/// Fake SMAppService seam: records transitions, simulates failures.
@MainActor
private final class FakeLoginItem: LoginItemRegistering {
    var registered = false
    var failOnRegister = false
    var failOnUnregister = false

    func register() throws {
        if failOnRegister {
            throw NSError(domain: "test", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "注册被系统拒绝"])
        }
        registered = true
    }

    func unregister() throws {
        if failOnUnregister {
            throw NSError(domain: "test", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "注销被系统拒绝"])
        }
        registered = false
    }

    func status() -> SMAppService.Status {
        registered ? .enabled : .notRegistered
    }
}

@MainActor
final class LoginItemServiceTests: XCTestCase {

    func testInitialStateReflectsSystemStatus() {
        let fake = FakeLoginItem()
        let service = LoginItemService(item: fake)
        XCTAssertFalse(service.isEnabled)
        XCTAssertNil(service.lastError)

        fake.registered = true
        let service2 = LoginItemService(item: fake)
        XCTAssertTrue(service2.isEnabled)
    }

    func testEnableRegistersAndPublishesStatus() {
        let fake = FakeLoginItem()
        let service = LoginItemService(item: fake)
        service.setEnabled(true)
        XCTAssertTrue(fake.registered)
        XCTAssertTrue(service.isEnabled)
        XCTAssertNil(service.lastError)
    }

    func testDisableUnregisters() {
        let fake = FakeLoginItem()
        fake.registered = true
        let service = LoginItemService(item: fake)
        service.setEnabled(false)
        XCTAssertFalse(fake.registered)
        XCTAssertFalse(service.isEnabled)
    }

    func testRegisterFailureSurfacesErrorAndSnapsToggleBack() {
        let fake = FakeLoginItem()
        fake.failOnRegister = true
        let service = LoginItemService(item: fake)
        service.setEnabled(true)
        XCTAssertFalse(service.isEnabled, "Toggle must reflect system status, not the attempted value")
        XCTAssertEqual(service.lastError, "注册被系统拒绝")
    }

    func testUnregisterFailureSurfacesErrorAndKeepsEnabled() {
        let fake = FakeLoginItem()
        fake.registered = true
        fake.failOnUnregister = true
        let service = LoginItemService(item: fake)
        service.setEnabled(false)
        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(service.lastError, "注销被系统拒绝")
    }

    func testAcknowledgeErrorClearsLast() {
        let fake = FakeLoginItem()
        fake.failOnRegister = true
        let service = LoginItemService(item: fake)
        service.setEnabled(true)
        XCTAssertNotNil(service.lastError)
        service.acknowledgeError()
        XCTAssertNil(service.lastError)
    }

    func testRefreshStatusPicksUpExternalChange() {
        let fake = FakeLoginItem()
        let service = LoginItemService(item: fake)
        XCTAssertFalse(service.isEnabled)
        // User toggles in System Settings → SMAppService status changes.
        fake.registered = true
        service.refreshStatus()
        XCTAssertTrue(service.isEnabled)
    }
}
