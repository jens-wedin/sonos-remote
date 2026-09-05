import Foundation
import Testing
@testable import SonosRemote

@Suite struct VolumeCommandGateTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func firstChangeSendsImmediately() {
        var gate = VolumeCommandGate()
        #expect(gate.userChanged(to: 10, at: t0) == 10)
        #expect(!gate.hasPending)
    }

    @Test func rapidChangesAreCoalescedUntilTheIntervalPasses() {
        var gate = VolumeCommandGate(minimumInterval: 0.1, suppressIncomingFor: 0.5)
        #expect(gate.userChanged(to: 10, at: t0) == 10)
        #expect(gate.userChanged(to: 11, at: t0.addingTimeInterval(0.02)) == nil)
        #expect(gate.userChanged(to: 12, at: t0.addingTimeInterval(0.05)) == nil)
        #expect(gate.hasPending)
        #expect(gate.flush(at: t0.addingTimeInterval(0.08)) == nil)
        #expect(gate.flush(at: t0.addingTimeInterval(0.11)) == 12)
        #expect(!gate.hasPending)
        #expect(gate.flush(at: t0.addingTimeInterval(0.5)) == nil)
    }

    @Test func changeAfterIntervalSendsDirectly() {
        var gate = VolumeCommandGate(minimumInterval: 0.1, suppressIncomingFor: 0.5)
        _ = gate.userChanged(to: 10, at: t0)
        #expect(gate.userChanged(to: 20, at: t0.addingTimeInterval(0.2)) == 20)
    }

    @Test func incomingIsSuppressedShortlyAfterASend() {
        var gate = VolumeCommandGate(minimumInterval: 0.1, suppressIncomingFor: 0.5)
        #expect(gate.shouldAcceptIncoming(at: t0))
        _ = gate.userChanged(to: 10, at: t0)
        #expect(!gate.shouldAcceptIncoming(at: t0.addingTimeInterval(0.3)))
        #expect(gate.shouldAcceptIncoming(at: t0.addingTimeInterval(0.5)))
    }
}
