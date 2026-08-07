import XCTest
import SwiftUI
@testable import DesignSystem

@MainActor
final class TypographyTests: XCTestCase {
    // MARK: - New constants exist and resolve to non-nil Font

    func testNewFontConstantsResolveToNonNilValues() {
        // Touch each constant so a runtime regression in the Font initializer
        // (returning nil on this SDK) would surface as a test failure rather
        // than a silent crash at a downstream call site.
        let fonts: [Font] = [
            AppFont.titleHero,
            AppFont.numberSize,
            AppFont.numberCaption,
            AppFont.bodyLarge
        ]
        for font in fonts {
            XCTAssertNotNil(font, "Every new AppFont constant must resolve to a non-nil Font")
        }
    }

    // MARK: - New constants render distinct glyphs (size/design differences)

    /// SwiftUI's `Font` is opaque on macOS 13 — `description` is identical for
    /// every `SystemProvider`. To prove the constants really do differ, we
    /// render each one into a CGImage via `ImageRenderer` and compare the
    /// resulting pixel hashes. Same size + same design + same text → same
    /// pixels; any of those three differing → different pixels.
    func testTitleHeroProducesDifferentPixelsThanLargeTitle() throws {
        let a = try renderPixelHash(of: "Hg", using: AppFont.titleHero)
        let b = try renderPixelHash(of: "Hg", using: AppFont.largeTitle)
        XCTAssertNotEqual(a, b, "titleHero (28pt) must render differently from largeTitle (26pt)")
    }

    func testNumberSizeProducesDifferentPixelsThanBody() throws {
        // 17pt rounded semibold vs. 13pt default — both size and design differ,
        // so the pixels must differ.
        let a = try renderPixelHash(of: "42", using: AppFont.numberSize)
        let b = try renderPixelHash(of: "42", using: AppFont.body)
        XCTAssertNotEqual(a, b, "numberSize (rounded design) must render differently from body (default)")
    }

    func testNumberCaptionProducesDifferentPixelsThanCaption() throws {
        // 11pt monospaced vs. 11pt default — only design differs, but that
        // still changes the glyph metrics for non-zero digits.
        let a = try renderPixelHash(of: "GB", using: AppFont.numberCaption)
        let b = try renderPixelHash(of: "GB", using: AppFont.caption)
        XCTAssertNotEqual(a, b, "numberCaption (monospaced) must render differently from caption (default)")
    }

    func testBodyLargeProducesDifferentPixelsThanBody() throws {
        // 15pt vs. 13pt — same default design, different size.
        let a = try renderPixelHash(of: "Hello", using: AppFont.bodyLarge)
        let b = try renderPixelHash(of: "Hello", using: AppFont.body)
        XCTAssertNotEqual(a, b, "bodyLarge (15pt) must render differently from body (13pt)")
    }

    // MARK: - Existing constants are preserved (regression guard)

    func testExistingFontConstantsAreStillPresent() {
        // Regression guard: do not let a future edit drop one of the
        // previously defined constants.
        let fonts: [Font] = [
            AppFont.icon,
            AppFont.display,
            AppFont.appIcon,
            AppFont.largeTitle,
            AppFont.title2,
            AppFont.title3,
            AppFont.body,
            AppFont.callout,
            AppFont.caption,
            AppFont.monoDigit
        ]
        for font in fonts {
            XCTAssertNotNil(font, "All pre-existing AppFont constants must remain resolvable")
        }
    }

    // MARK: - Helpers

    /// Renders `text` in the supplied font to a 64×32 CGImage and returns a
    /// stable hash of its pixel bytes. Two different fonts (different size or
    /// design) produce different hashes; identical inputs produce identical
    /// hashes. The image is opaque enough (64×32) for typical 11–28pt
    /// ascenders/descenders without clipping.
    private func renderPixelHash(of text: String, using font: Font) throws -> UInt64 {
        let view = Text(text)
            .font(font)
            .foregroundColor(.black)
            .frame(width: 64, height: 32)
            .background(Color.white)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 64, height: 32)
        guard let cgImage = renderer.cgImage else {
            XCTFail("ImageRenderer failed to produce a CGImage for font \(font)")
            throw NSError(domain: "TypographyTests", code: 1)
        }
        return hash(image: cgImage)
    }

    /// FNV-1a 64-bit hash of every byte in the image. Deterministic across
    /// runs; good enough for "is this the same image" comparisons.
    private func hash(image: CGImage) -> UInt64 {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return 0 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0xcbf29ce484222325
        for byte in pixels {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}
