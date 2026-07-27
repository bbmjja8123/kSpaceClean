import XCTest
@testable import kSpaceClean
import DesignSystem

final class RuleClassifierTests: XCTestCase {
    let classifier = RuleClassifier()

    // MARK: - File Category Classification

    func test_classify_imageExtensions() {
        let urls = [
            URL(filePath: "/test/photo.jpg"),
            URL(filePath: "/test/photo.png"),
            URL(filePath: "/test/photo.gif"),
            URL(filePath: "/test/photo.webp"),
            URL(filePath: "/test/photo.heic"),
        ]
        for url in urls {
            let result = classifier.classify(url)
            XCTAssertEqual(result, .image, "Expected .image for \(url.pathExtension)")
        }
    }

    func test_classify_videoExtensions() {
        let urls = [
            URL(filePath: "/test/video.mp4"),
            URL(filePath: "/test/video.mov"),
            URL(filePath: "/test/video.avi"),
            URL(filePath: "/test/video.mkv"),
            URL(filePath: "/test/video.webm"),
        ]
        for url in urls {
            let result = classifier.classify(url)
            XCTAssertEqual(result, .video, "Expected .video for \(url.pathExtension)")
        }
    }

    func test_classify_documentExtensions() {
        let urls = [
            URL(filePath: "/test/doc.pdf"),
            URL(filePath: "/test/doc.docx"),
            URL(filePath: "/test/doc.xlsx"),
            URL(filePath: "/test/doc.txt"),
            URL(filePath: "/test/doc.md"),
            URL(filePath: "/test/doc.json"),
            URL(filePath: "/test/doc.csv"),
        ]
        for url in urls {
            let result = classifier.classify(url)
            XCTAssertEqual(result, .document, "Expected .document for \(url.pathExtension)")
        }
    }

    func test_classify_audioExtensions() {
        let urls = [
            URL(filePath: "/test/audio.mp3"),
            URL(filePath: "/test/audio.wav"),
            URL(filePath: "/test/audio.aac"),
            URL(filePath: "/test/audio.flac"),
            URL(filePath: "/test/audio.m4a"),
        ]
        for url in urls {
            let result = classifier.classify(url)
            XCTAssertEqual(result, .audio, "Expected .audio for \(url.pathExtension)")
        }
    }

    func test_classify_cacheExtensions() {
        let urls = [
            URL(filePath: "/test/cache.cache"),
            URL(filePath: "/test/cache.tmp"),
            URL(filePath: "/test/cache.log"),
            URL(filePath: "/test/cache.swp"),
        ]
        for url in urls {
            let result = classifier.classify(url)
            XCTAssertEqual(result, .cache, "Expected .cache for \(url.pathExtension)")
        }
    }

    func test_classify_devExtensions() {
        let urls = [
            URL(filePath: "/test/source.swift"),
            URL(filePath: "/test/source.cpp"),
            URL(filePath: "/test/source.h"),
            URL(filePath: "/test/source.js"),
            URL(filePath: "/test/source.ts"),
            URL(filePath: "/test/source.py"),
            URL(filePath: "/test/source.go"),
            URL(filePath: "/test/source.rs"),
            URL(filePath: "/test/source.kt"),
        ]
        for url in urls {
            let result = classifier.classify(url)
            XCTAssertEqual(result, .dev, "Expected .dev for \(url.pathExtension)")
        }
    }

    func test_classify_unknownExtension_returnsOther() {
        let url = URL(filePath: "/test/file.xyz123")
        let result = classifier.classify(url)
        XCTAssertEqual(result, .other)
    }

    func test_classify_noExtension_returnsOther() {
        let url = URL(filePath: "/test/README")
        let result = classifier.classify(url)
        XCTAssertEqual(result, .other)
    }

    // MARK: - System Cache Detection

    func test_isSystemCache_knownCachePaths() {
        let paths = [
            "/Library/Caches/com.example/test",
            "/Users/test/Library/Caches/test",
        ]
        for path in paths {
            let url = URL(filePath: path)
            XCTAssertTrue(classifier.isSystemCache(url), "Expected \(path) to be system cache")
        }
    }

    func test_isSystemCache_normalPath_returnsFalse() {
        let url = URL(filePath: "/Users/test/Documents/file.txt")
        XCTAssertFalse(classifier.isSystemCache(url))
    }

    // MARK: - Edge Cases

    func test_classify_emptyPath() {
        let url = URL(filePath: "")
        let result = classifier.classify(url)
        XCTAssertEqual(result, .other)
    }

    func test_classify_caseInsensitive() {
        let url = URL(filePath: "/test/photo.JPG")
        let result = classifier.classify(url)
        XCTAssertEqual(result, .image)
    }

    func test_classify_cachePathWithDevExtension() {
        // Files with cache extensions should be .cache regardless of path
        let url = URL(filePath: "/Library/Caches/com.example/test.cache")
        let result = classifier.classify(url)
        XCTAssertEqual(result, .cache)
    }
}
