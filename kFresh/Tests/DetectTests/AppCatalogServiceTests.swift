import XCTest
@testable import kFresh

final class AppCatalogServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testClassifyHomebrewCaskApp() {
        let url = URL(fileURLWithPath: "/opt/homebrew/Caskroom/foo/Foo.app")
        let source = AppCatalogService.classifySource(url: url, bundleID: "com.example.foo")
        XCTAssertEqual(source, .homebrew)
    }

    func testClassifySetappApp() {
        let url = URL(fileURLWithPath: "/Applications/Setapp/Foo.app")
        let source = AppCatalogService.classifySource(url: url, bundleID: "com.setapp.Foo")
        XCTAssertEqual(source, .setapp)
    }

    func testClassifyDeveloperIDApp() {
        let url = URL(fileURLWithPath: "/Applications/Foo.app")
        let source = AppCatalogService.classifySource(url: url, bundleID: "com.example.foo")
        XCTAssertEqual(source, .userInstalled)
    }

    func testClassifyAppStoreApp() throws {
        let appPath = tempDir.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: appPath, withIntermediateDirectories: true)
        let receiptDir = appPath.appendingPathComponent("Contents/_MASReceipt")
        try FileManager.default.createDirectory(at: receiptDir, withIntermediateDirectories: true)
        try Data().write(to: receiptDir.appendingPathComponent("receipt"))

        let source = AppCatalogService.classifySource(url: appPath, bundleID: "com.example.test")
        XCTAssertEqual(source, .mas)
    }

    // `async` added: the brief declared this `throws` only, but the body awaits an actor method.
    func testSizeOfAppCalculatesRecursiveSize() async throws {
        let appPath = tempDir.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: appPath, withIntermediateDirectories: true)
        try Data(count: 1000).write(to: appPath.appendingPathComponent("file1.bin"))
        let nested = appPath.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(count: 500).write(to: nested.appendingPathComponent("file2.bin"))

        let service = AppCatalogService()
        let size = await service.sizeOfApp(at: appPath)
        XCTAssertGreaterThanOrEqual(size, 1500)
    }
}
