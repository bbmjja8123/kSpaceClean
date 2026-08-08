import XCTest
@testable import kWise

final class DangerousConfirmDialogTests: XCTestCase {
    func test_requiresExactDELETEInput() {
        XCTAssertTrue(DangerousConfirmDialog.isConfirmationValid("DELETE"))
        XCTAssertFalse(DangerousConfirmDialog.isConfirmationValid("delete"))
        XCTAssertFalse(DangerousConfirmDialog.isConfirmationValid(" DELETE "))
        XCTAssertFalse(DangerousConfirmDialog.isConfirmationValid(""))
    }
}
