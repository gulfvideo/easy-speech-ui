import Foundation

/// Carries a non-Sendable value across a `@Sendable` boundary where the surrounding
/// code guarantees single-threaded access. Used only for CoreAudio buffers handed
/// synchronously back to the caller that produced them.
struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// A mutable flag usable inside a synchronously-invoked `@Sendable` closure.
final class UncheckedFlag: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool = false) { self.value = value }
}
