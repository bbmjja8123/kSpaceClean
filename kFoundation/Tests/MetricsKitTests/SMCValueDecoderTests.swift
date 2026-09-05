import XCTest
@testable import MetricsKit

final class SMCValueDecoderTests: XCTestCase {
    // sp78: signed 7.8 fixed-point, big-endian 2 bytes. 0x30 0x00 = 48.0°C
    func testDecodeSP78() {
        XCTAssertEqual(try XCTUnwrap(SMCValueDecoder.decode(type: "sp78", data: [0x30, 0x00])), 48.0, accuracy: 0.0001)
        // 0xEC00 = -5120 → -5120/256 = -20.0; 0xFB00 = -1280 → -5.0
        XCTAssertEqual(try XCTUnwrap(SMCValueDecoder.decode(type: "sp78", data: [0xEC, 0x00])), -20.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(SMCValueDecoder.decode(type: "sp78", data: [0xFB, 0x00])), -5.0, accuracy: 0.0001)
    }

    // fpe2: signed fixed-point with 2 fractional bits, big-endian 2 bytes.
    // 0x0E 0x10 = 3600 → 3600/4 = 900 RPM
    func testDecodeFPE2() {
        XCTAssertEqual(try XCTUnwrap(SMCValueDecoder.decode(type: "fpe2", data: [0x0E, 0x10])), 900.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(SMCValueDecoder.decode(type: "fpe2", data: [0xFF, 0xFC])), -1.0, accuracy: 0.0001)
    }

    // Fixed-point convention: the trailing hex digit of the tag is the
    // fractional-bit count → divisor = 2^digit.
    // fp4c → 'c' = 12 → 4096; fp1f → 'f' = 15 → 32768; fp5a → 'a' = 10 → 1024.
    func testDecodeFixedPointTrailingDigitDivisors() {
        // fp4c: 0x10 0x00 = 4096 raw → 4096/4096 = 1.0; 0x48 0x00 = 18432/4096 = 4.5
        XCTAssertEqual(try XCTUnwrap(SMCValueDecoder.decode(type: "fp4c", data: [0x10, 0x00])), 1.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(SMCValueDecoder.decode(type: "fp4c", data: [0x48, 0x00])), 4.5, accuracy: 0.0001)
        // fp1f: 0x80 0x00 = -32768 raw → -32768/32768 = -1.0
        XCTAssertEqual(try XCTUnwrap(SMCValueDecoder.decode(type: "fp1f", data: [0x80, 0x00])), -1.0, accuracy: 0.0001)
        // fp5a: 0x0A 0x00 = 2560 raw → 2560/1024 = 2.5
        XCTAssertEqual(try XCTUnwrap(SMCValueDecoder.decode(type: "fp5a", data: [0x0A, 0x00])), 2.5, accuracy: 0.0001)
    }

    // flt : 32-bit IEEE754 little-endian
    func testDecodeFloat() {
        let f: Float = 55.5
        let bytes = withUnsafeBytes(of: f.bitPattern.littleEndian) { Array($0) }
        XCTAssertEqual(try XCTUnwrap(SMCValueDecoder.decode(type: "flt ", data: bytes)), 55.5, accuracy: 0.001)
    }

    // ui8 / ui16
    func testDecodeUnsigned() {
        XCTAssertEqual(try XCTUnwrap(SMCValueDecoder.decode(type: "ui8", data: [0x64])), 100.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(SMCValueDecoder.decode(type: "ui16", data: [0x01, 0x90])), 400.0, accuracy: 0.0001)
    }

    func testUnknownTypeReturnsNil() {
        XCTAssertNil(SMCValueDecoder.decode(type: "!!!!", data: [0, 0]))
        XCTAssertNil(SMCValueDecoder.decode(type: "sp78", data: []))
    }
}
