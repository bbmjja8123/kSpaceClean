import Foundation
@testable import kWatch

/// Thread-safe box for capturing mutable state in @Sendable closures during tests.
final class SendableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
