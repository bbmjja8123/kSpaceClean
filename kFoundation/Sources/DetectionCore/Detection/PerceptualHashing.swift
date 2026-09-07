import CoreGraphics
import Foundation

/// Shared perceptual-hash primitives used by both the image
/// (`PerceptualDetector`) and video (`SimilarVideoDetector`) pipelines.
/// Extracted so the 9×8 dHash definition and hamming metric stay
/// identical across media types.
enum PerceptualHashing {
    /// 64-bit difference hash of a grayscale 9×8 downscale: row-wise
    /// "left pixel brighter than right" bits. Deterministic for a given
    /// bitmap; interpolation quality is intentionally low for speed and
    /// resilience to small resizes.
    static func dHash(of image: CGImage) -> UInt64? {
        guard let context = CGContext(
            data: nil,
            width: 9,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 9,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: 9, height: 8))
        guard let data = context.data else { return nil }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var hash: UInt64 = 0
        var bit = 0

        for row in 0..<8 {
            for column in 0..<8 {
                if pixels[row * 9 + column] > pixels[row * 9 + column + 1] {
                    hash |= UInt64(1) << UInt64(bit)
                }
                bit += 1
            }
        }
        return hash
    }

    /// Popcount of the XOR — the standard dHash distance metric.
    static func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }
}
