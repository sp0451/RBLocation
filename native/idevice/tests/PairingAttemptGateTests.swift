import Foundation

@main
enum PairingAttemptGateTests {
    static func main() {
        var gate = PairingAttemptGate()
        let first = gate.begin(operationId: "pairing-1")
        precondition(first.operationId == "pairing-1")
        precondition(gate.accepts(first), "Current attempt callback should be delivered")

        gate.invalidate()
        precondition(!gate.accepts(first), "Cancellation must drop an already queued PIN callback")
        let second = gate.begin(operationId: "pairing-2")
        precondition(gate.accepts(second))
        precondition(!gate.accepts(first), "A late first-attempt callback must not revive during re-pairing")

        gate.invalidate()
        let reusedId = gate.begin(operationId: "pairing-2")
        precondition(reusedId.token != second.token)
        precondition(!gate.accepts(second), "Even a repeated public operation ID must not accept the old native attempt")
        precondition(gate.accepts(reusedId))

        gate.invalidate()
        gate.invalidate()
        precondition(!gate.accepts(reusedId), "Repeated teardown must keep all old callbacks invalid")
        print("Pairing attempt gate: current delivery, cancellation, retry, reused ID and repeated teardown passed.")
    }
}
