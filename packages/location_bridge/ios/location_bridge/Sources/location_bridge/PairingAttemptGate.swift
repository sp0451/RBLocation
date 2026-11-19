import Foundation

struct PairingAttempt: Equatable, Sendable {
    let operationId: String
    let token: UUID
}

/// A transport callback can outlive cancellation and arrive during another attempt.
/// Use a fresh native token even when a caller accidentally reuses its operation ID.
struct PairingAttemptGate {
    private var current: PairingAttempt?

    mutating func begin(operationId: String) -> PairingAttempt {
        let attempt = PairingAttempt(operationId: operationId, token: UUID())
        current = attempt
        return attempt
    }

    mutating func invalidate() { current = nil }
    func accepts(_ attempt: PairingAttempt) -> Bool { current == attempt }
}
