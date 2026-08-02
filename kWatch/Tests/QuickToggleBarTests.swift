import XCTest
@testable import kWatch

final class QuickToggleBarTests: XCTestCase {

    func testReadWiFiReturnsBool() {
        // Smoke test: function returns a Bool without crashing.
        let _ = QuickToggleBar.readWiFi()
    }

    func testSetWiFiDoesNotCrash() {
        QuickToggleBar.setWiFi(true)
        QuickToggleBar.setWiFi(false)
    }

    func testSetBluetoothDoesNotCrash() {
        QuickToggleBar.setBluetooth(true)
    }
}
