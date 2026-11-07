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
            setPosition: { positions.append($0) }
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
            setPosition: { point in calls.append("position \(point.x),\(point.y)") }
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
            setPosition: { point in calls.append("position \(point.x),\(point.y)") }
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
            setPosition: { point in calls.append("position \(point.x),\(point.y)") }
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
            setPosition: { point in calls.append("position \(point.x),\(point.y)") }
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
            setPosition: { _ in calls.append("position") }
        )

        #expect(calls.isEmpty)
    }
}