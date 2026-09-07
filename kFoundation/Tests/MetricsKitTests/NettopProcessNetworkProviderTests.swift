import XCTest
@testable import MetricsKit

/// Tests for the public JSON parser on `NettopProcessNetworkProvider`.
///
/// `parse(_:)` is the stable, side-effect-free contract that
/// `sampleCumulative()` and `sampleThroughput()` both delegate to. We
/// test it directly so a regression in the wire format shows up here
/// before it reaches a real `nettop` invocation.
final class NettopProcessNetworkProviderTests: XCTestCase {

    /// Happy path — multiple PIDs, each with multiple connections that
    /// should aggregate per PID.
    func testParseAggregatesAcrossConnectionsPerPID() throws {
        let json = """
        [
          {
            "tcp4.tcp4.1234": {"bytes_in": 1000, "bytes_out": 200},
            "tcp4.tcp4.5678": {"bytes_in": 300, "bytes_out": 50}
          },
          {
            "tcp4.tcp4.1234": {"bytes_in": 500, "bytes_out": 100}
          }
        ]
        """
        let result = try NettopProcessNetworkProvider.parse(json)
        XCTAssertEqual(result[1234]?.download, 1500)
        XCTAssertEqual(result[1234]?.upload, 300)
        XCTAssertEqual(result[5678]?.download, 300)
        XCTAssertEqual(result[5678]?.upload, 50)
    }

    /// `nettop` emits connection keys like `tcp6.tcp6.99`. The PID is the
    /// last `.`-separated segment.
    func testParseHandlesNonTcp4Prefixes() throws {
        let json = """
        [
          {"udp.udp.42": {"bytes_in": 0, "bytes_out": 99}}
        ]
        """
        let result = try NettopProcessNetworkProvider.parse(json)
        XCTAssertEqual(result[42]?.upload, 99)
    }

    /// Malformed input should return an empty map rather than throw so a
    /// transient nettop error doesn't crash the dashboard refresh path.
    func testParseReturnsEmptyMapOnMalformedJSON() throws {
        let result = try NettopProcessNetworkProvider.parse("not json at all")
        XCTAssertTrue(result.isEmpty)
    }

    /// Empty JSON array — still produces an empty result.
    func testParseEmptyArray() throws {
        let result = try NettopProcessNetworkProvider.parse("[]")
        XCTAssertTrue(result.isEmpty)
    }

    /// Connection keys that don't end in a PID integer are ignored.
    func testParseIgnoresKeysWithoutPIDSegment() throws {
        let json = """
        [
          {"tcp4.tcp4.not_a_pid": {"bytes_in": 100, "bytes_out": 100}}
        ]
        """
        let result = try NettopProcessNetworkProvider.parse(json)
        XCTAssertTrue(result.isEmpty)
    }
}