import CoreGraphics
import Testing
@testable import ApolloShellCore

@Suite("Window guard clamp application")
struct WindowGuardApplicationPlanTests {
    private let current = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let bottomTarget = CGRect(x: 0, y: 0, width: 1512, height: 938)

    @Test("a move-only clamp positions the target normally")
    func moveOnlyClampPositionsTarget() {
        let plan = WindowClampApplicationPlan(
            current: CGRect(x: 100, y: 700, width: 500, height: 300),
            target: CGRect(x: 100, y: 638, width: 500, height: 300)
        )
        var positions: [CGPoint] = []

        plan.apply(
            canSetPosition: true,
            canSetSize: { Issue.record("a move-only clamp must not ask about resizing"); return false },
            setSize: { _ in Issue.record("a move-only clamp must not resize"); return false },
            setPosition: { positions.append($0); return true }
        )

        #expect(positions == [CGPoint(x: 100, y: 638)])
    }

    @Test("an accepted height-only resize happens before the target move")
    func acceptedHeightOnlyResizePrecedesTargetMove() {
        let plan = WindowClampApplicationPlan(current: current, target: bottomTarget)
        var calls: [String] = []

        plan.apply(
            canSetPosition: true,
            canSetSize: { true },
            setSize: { size in calls.append("size \(size.width)x\(size.height)"); return true },
            readFrame: { bottomTarget },
            setPosition: { point in calls.append("position \(point.x),\(point.y)"); return true }
        )

        #expect(calls == ["size 1512.0x938.0", "position 0.0,0.0"])
    }

    @Test("an unsettable height-only resize skips size and moves above the bottom strip")
    func unsettableHeightOnlyResizeUsesSafeFallback() {
        let plan = WindowClampApplicationPlan(current: current, target: bottomTarget)
        var calls: [String] = []

        plan.apply(
            canSetPosition: true,
            canSetSize: { false },
            setSize: { _ in calls.append("size"); return true },
            setPosition: { point in calls.append("position \(point.x),\(point.y)"); return true }
        )

        #expect(calls == ["position 0.0,-44.0"])
    }

    @Test("a rejected height-only resize moves above the bottom strip")
    func rejectedHeightOnlyResizeUsesSafeFallback() {
        let plan = WindowClampApplicationPlan(current: current, target: bottomTarget)
        var calls: [String] = []

        plan.apply(
            canSetPosition: true,
            canSetSize: { true },
            setSize: { _ in calls.append("size"); return false },
            setPosition: { point in calls.append("position \(point.x),\(point.y)"); return true }
        )

        #expect(calls == ["size", "position 0.0,-44.0"])
    }

    @Test("a rejected width resize keeps the existing side-bar target position")
    func rejectedWidthResizeKeepsTargetPosition() {
        let plan = WindowClampApplicationPlan(
            current: CGRect(x: 0, y: 30, width: 1512, height: 952),
            target: CGRect(x: 44, y: 30, width: 1468, height: 952)
        )
        var calls: [String] = []

        plan.apply(
            canSetPosition: true,
            canSetSize: { true },
            setSize: { _ in calls.append("size"); return false },
            setPosition: { point in calls.append("position \(point.x),\(point.y)"); return true }
        )

        #expect(calls == ["size", "position 44.0,30.0"])
    }

    @Test("an unsettable position performs no resize or move")
    func unsettablePositionPerformsNoOperations() {
        let plan = WindowClampApplicationPlan(current: current, target: bottomTarget)
        var calls: [String] = []

        plan.apply(
            canSetPosition: false,
            canSetSize: { calls.append("can size"); return true },
            setSize: { _ in calls.append("size"); return true },
            setPosition: { _ in calls.append("position"); return true }
        )

        #expect(calls.isEmpty)
    }

    @Test("a successful resize with unchanged height uses the bottom-safe actual-frame fallback")
    func successfulResizeWithUnchangedHeightUsesActualFrameFallback() {
        let plan = WindowClampApplicationPlan(current: current, target: bottomTarget)
        var calls: [String] = []

        let applied = plan.apply(
            canSetPosition: true,
            canSetSize: { true },
            setSize: { _ in calls.append("size"); return true },
            readFrame: { current },
            setPosition: { point in calls.append("position \(point.x),\(point.y)"); return true }
        )

        #expect(applied)
        #expect(calls == ["size", "position 0.0,-44.0"])
    }

    @Test("a successful partial height resize uses the partial actual height for bottom-safe fallback")
    func successfulPartialHeightResizeUsesActualFrameFallback() {
        let plan = WindowClampApplicationPlan(current: current, target: bottomTarget)
        var calls: [String] = []
        let partial = CGRect(x: 0, y: 0, width: 1512, height: 960)

        let applied = plan.apply(
            canSetPosition: true,
            canSetSize: { true },
            setSize: { _ in calls.append("size"); return true },
            readFrame: { partial },
            setPosition: { point in calls.append("position \(point.x),\(point.y)"); return true }
        )

        #expect(applied)
        #expect(calls == ["size", "position 0.0,-22.0"])
    }

    @Test("a failed position write reports failure so callers do not record a synthetic target")
    func failedPositionWriteReportsFailure() {
        let plan = WindowClampApplicationPlan(
            current: CGRect(x: 100, y: 700, width: 500, height: 300),
            target: CGRect(x: 100, y: 638, width: 500, height: 300)
        )
        var attempted: [CGPoint] = []
        var ledger = ClampLedger<String>()

        let applied = plan.apply(
            canSetPosition: true,
            canSetSize: { Issue.record("a move-only clamp must not ask about resizing"); return false },
            setSize: { _ in Issue.record("a move-only clamp must not resize"); return false },
            setPosition: { point in attempted.append(point); return false }
        )

        #expect(!applied)
        #expect(attempted == [CGPoint(x: 100, y: 638)])
        if applied {
            ledger.record("window", result: CGRect(x: 100, y: 638, width: 500, height: 300), now: 1)
        }
        #expect(ledger.count == 0)
    }
}