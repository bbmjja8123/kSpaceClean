import XCTest
@testable import kWatch

final class QuickToggleBarTests: XCTestCase {

    func testReadWiFiReturnsBool() {
        // Smoke test: function returns a Bool without crashing.
        let _ = QuickToggleBar.readWiFi()
    }

    func testSetWiFiDoesNotCrash() {
        let original = QuickToggleBar.readWiFi()
        QuickToggleBar.setWiFi(true)
        QuickToggleBar.setWiFi(false)
        QuickToggleBar.setWiFi(original)
    }

    func testSetBluetoothDoesNotCrash() {
        QuickToggleBar.setBluetooth(true)
    }
}
