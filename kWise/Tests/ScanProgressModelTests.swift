import XCTest
@testable import kWise

final class ScanProgressModelTests: XCTestCase {
    func test_scanStage_allCases() {
        XCTAssertEqual(ScanStage.allCases.count, 8)
    }

    func test_scanStage_displayNames() {
        XCTAssertEqual(ScanStage.cache.title, "缓存扫描")
        XCTAssertEqual(ScanStage.devJunk.title, "开发残留")
        XCTAssertEqual(ScanStage.binary.title, "二进制文件")
        XCTAssertEqual(ScanStage.language.title, "语言包")
        XCTAssertEqual(ScanStage.brokenConfig.title, "损坏配置")
        XCTAssertEqual(ScanStage.iosCache.title, "iOS 缓存")
        XCTAssertEqual(ScanStage.appLeftovers.title, "应用残留")
        XCTAssertEqual(ScanStage.browserCache.title, "浏览器缓存")
    }

    func test_scanStats_defaults() {
        let stats = ScanStats()
        XCTAssertEqual(stats.discoveredSize, 0)
        XCTAssertEqual(stats.fileCount, 0)
        XCTAssertEqual(stats.elapsed, 0)
        XCTAssertEqual(stats.filesPerSecond, 0)
    }

    func test_scanProgress_hasCurrentNodePath() {
        var progress = ScanProgress()
        XCTAssertNil(progress.currentNodePath)
        progress.currentNodePath = "/private/var/log/test.log"
        XCTAssertEqual(progress.currentNodePath, "/private/var/log/test.log")
    }

    func test_scanProgress_hasCurrentStage() {
        var progress = ScanProgress()
        XCTAssertEqual(progress.currentStage, .cache)
        progress.currentStage = .devJunk
        XCTAssertEqual(progress.currentStage, .devJunk)
    }
}
