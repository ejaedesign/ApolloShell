import CoreGraphics
import Testing
@testable import ApolloShellCore

@Suite("Bottom dock hover and concealment")
struct BottomDockHoverTests {
    private let left = BottomDockDisplay(id: "left", frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    private let right = BottomDockDisplay(id: "right", frame: CGRect(x: 200, y: 0, width: 100, height: 100))
    private let touchingRight = BottomDockDisplay(id: "touching-right", frame: CGRect(x: 100, y: 0, width: 100, height: 100))
    private let configuration = BottomDockConfiguration(
        dockThickness: 20,
        bottomBleed: 10,
        timing: BottomDockTiming(revealDwell: 0.2, hideGrace: 0.4)
    )

    private func model(_ displays: [BottomDockDisplay] = []) -> BottomDockModel {
        BottomDockModel(displays: displays.isEmpty ? [left] : displays, configuration: configuration)
    }

    private func revealed(_ display: BottomDockDisplay = BottomDockDisplay(id: "left", frame: CGRect(x: 0, y: 0, width: 100, height: 100))) -> BottomDockModel {
        let pending = BottomDockReducer.reduce(
            model([display]),
            event: .pointerMoved(CGPoint(x: display.frame.midX, y: display.frame.minY - 5))
        )
        let token = pending.model.state(for: display.id)!.generation
        return BottomDockReducer.reduce(pending.model, event: .revealTimerFired(display: display.id, token: token)).model
    }

    @Test("ownership is explicit, gaps stay unowned, and a shared edge belongs only to its next display")
    func ownershipDoesNotJumpAcrossDisplays() {
        #expect(BottomDockGeometry.displayOwning(CGPoint(x: 99, y: 10), among: [left, touchingRight]) == left.id)
        #expect(BottomDockGeometry.displayOwning(CGPoint(x: 100, y: 10), among: [left, touchingRight]) == touchingRight.id)
        #expect(BottomDockGeometry.displayOwning(CGPoint(x: 150, y: 10), among: [left, right]) == nil)
        #expect(BottomDockGeometry.displayOwning(CGPoint(x: 100, y: 10), among: [touchingRight, left]) == touchingRight.id)
    }

    @Test("an exterior bleed creates an exterior trigger, while blocked bleed uses a narrow interior trigger")
    func triggerGeometryUsesInteriorFallbackWhenBleedIsBlocked() {
        let exterior = BottomDockGeometry.areas(for: left, dockThickness: 20, bottomBleed: 10)
        let blocked = BottomDockGeometry.areas(for: left, dockThickness: 20, bottomBleed: 0)
        let displayBelow = BottomDockDisplay(id: "below", frame: CGRect(x: 0, y: -100, width: 100, height: 100))

        #expect(exterior.usesExteriorTrigger)
        #expect(exterior.trigger.contains(CGPoint(x: 50, y: -5)))
        #expect(exterior.keep.contains(CGPoint(x: 50, y: -5)))
        #expect(BottomDockGeometry.availableBottomBleed(for: left, among: [left, displayBelow], requested: 10) == 0)
        #expect(!blocked.usesExteriorTrigger)
        #expect(!blocked.trigger.contains(CGPoint(x: 50, y: -1)))
        #expect(blocked.trigger.height == BottomDockGeometry.interiorTriggerThickness)
        #expect(blocked.trigger.contains(CGPoint(x: 50, y: 1)))
        #expect(!blocked.trigger.contains(CGPoint(x: 50, y: 3)))
    }

    @Test("blocked bleed is decided independently for each selected dock in the reducer")
    func perDisplayBleedDoesNotDisableOtherDocks() {
        let belowLeft = BottomDockDisplay(id: "below-left", frame: CGRect(x: 0, y: -100, width: 100, height: 100))
        let initial = BottomDockModel(
            displays: [left, right],
            physicalDisplays: [left, right, belowLeft],
            configuration: configuration
        )
        let blocked = BottomDockReducer.reduce(initial, event: .pointerMoved(CGPoint(x: 50, y: -5)))
        let available = BottomDockReducer.reduce(blocked.model, event: .pointerMoved(CGPoint(x: 250, y: -5)))

        #expect(blocked.model.state(for: left.id)?.phase == .concealed)
        #expect(blocked.actions.isEmpty)
        #expect(available.model.state(for: right.id)?.phase == .revealPending)
        #expect(available.actions == [.scheduleReveal(display: right.id, token: 1, after: 0.2)])
    }

    @Test("a concealed dock reveals only after its dwell timer fires")
    func concealedToRevealedAfterDwell() {
        let pending = BottomDockReducer.reduce(model(), event: .pointerMoved(CGPoint(x: 50, y: -5)))
        let token = pending.model.state(for: left.id)!.generation

        #expect(pending.model.state(for: left.id)?.phase == .revealPending)
        #expect(pending.actions == [.scheduleReveal(display: left.id, token: token, after: 0.2)])

        let revealed = BottomDockReducer.reduce(pending.model, event: .revealTimerFired(display: left.id, token: token))
        #expect(revealed.model.state(for: left.id)?.phase == .revealed)
        #expect(revealed.actions == [.reveal(display: left.id)])
    }

    @Test("leaving a revealed dock schedules concealment after exit grace")
    func exitGraceConceals() {
        let visible = revealed()
        let pending = BottomDockReducer.reduce(visible, event: .pointerMoved(CGPoint(x: 150, y: 50)))
        let token = pending.model.state(for: left.id)!.generation

        #expect(pending.model.state(for: left.id)?.phase == .hidePending)
        #expect(pending.actions == [.scheduleHide(display: left.id, token: token, after: 0.4)])

        let hidden = BottomDockReducer.reduce(pending.model, event: .hideTimerFired(display: left.id, token: token))
        #expect(hidden.model.state(for: left.id)?.phase == .concealed)
        #expect(hidden.actions == [.conceal(display: left.id)])
    }

    @Test("moving from a display trigger into its keep area preserves the same pending reveal")
    func sameDisplayTransferKeepsDwell() {
        let started = BottomDockReducer.reduce(model(), event: .pointerMoved(CGPoint(x: 50, y: -5)))
        let token = started.model.state(for: left.id)!.generation
        let transferred = BottomDockReducer.reduce(started.model, event: .pointerMoved(CGPoint(x: 50, y: 10)))

        #expect(transferred.model.state(for: left.id)?.phase == .revealPending)
        #expect(transferred.model.state(for: left.id)?.generation == token)
        #expect(transferred.actions.isEmpty)
    }

    @Test("cross-display transfer hides the old display on grace and begins the new display dwell")
    func crossDisplayTransferIsPerDisplay() {
        let leftPending = BottomDockReducer.reduce(model([left, touchingRight]), event: .pointerMoved(CGPoint(x: 50, y: -5)))
        let leftToken = leftPending.model.state(for: left.id)!.generation
        let visibleLeft = BottomDockReducer.reduce(leftPending.model, event: .revealTimerFired(display: left.id, token: leftToken)).model
        let transferred = BottomDockReducer.reduce(visibleLeft, event: .pointerMoved(CGPoint(x: 150, y: -5)))
        let hideToken = transferred.model.state(for: left.id)!.generation
        let revealToken = transferred.model.state(for: touchingRight.id)!.generation

        #expect(transferred.model.state(for: left.id)?.phase == .hidePending)
        #expect(transferred.model.state(for: touchingRight.id)?.phase == .revealPending)
        #expect(transferred.actions == [
            .scheduleHide(display: left.id, token: hideToken, after: 0.4),
            .scheduleReveal(display: touchingRight.id, token: revealToken, after: 0.2),
        ])
    }

    @Test("a pointer gap belongs to no display and starts the visible display exit grace")
    func pointerGapDoesNotBorrowAnAdjacentDisplay() {
        let visibleLeft = revealed(left)
        let gap = BottomDockReducer.reduce(visibleLeft, event: .pointerMoved(CGPoint(x: 150, y: 10)))

        let gapToken = gap.model.state(for: left.id)!.generation
        #expect(gap.model.pointerDisplay == nil)
        #expect(gap.model.state(for: left.id)?.phase == .hidePending)
        #expect(gap.actions == [.scheduleHide(display: left.id, token: gapToken, after: 0.4)])
    }

    @Test("pointer leave cancels reveal, starts exit grace, and respects an active lease")
    func pointerLeaveTransitions() {
        let pending = BottomDockReducer.reduce(model(), event: .pointerMoved(CGPoint(x: 50, y: -5)))
        let revealToken = pending.model.state(for: left.id)!.generation
        let cancelled = BottomDockReducer.reduce(pending.model, event: .pointerLeft)
        let visible = revealed()
        let hiding = BottomDockReducer.reduce(visible, event: .pointerLeft)
        let hideToken = hiding.model.state(for: left.id)!.generation
        let leased = BottomDockReducer.reduce(visible, event: .interactionLeaseChanged(display: left.id, lease: .nativeMenu, isActive: true))
        let retained = BottomDockReducer.reduce(leased.model, event: .pointerLeft)

        #expect(cancelled.model.state(for: left.id)?.phase == .concealed)
        #expect(cancelled.actions == [.cancelReveal(display: left.id, token: revealToken)])
        #expect(hiding.model.state(for: left.id)?.phase == .hidePending)
        #expect(hiding.actions == [.scheduleHide(display: left.id, token: hideToken, after: 0.4)])
        #expect(retained.model.state(for: left.id)?.phase == .revealed)
        #expect(retained.actions.isEmpty)
    }

    @Test("fullscreen cancels pending work, then re-evaluates a resting pointer on exit")
    func fullscreenSuppressesAndReevaluatesOnExit() {
        let pending = BottomDockReducer.reduce(model(), event: .pointerMoved(CGPoint(x: 50, y: -5)))
        let token = pending.model.state(for: left.id)!.generation
        let suppressed = BottomDockReducer.reduce(pending.model, event: .fullscreenEntered(display: left.id))

        #expect(suppressed.model.state(for: left.id)?.phase == .fullscreenSuppressed)
        #expect(suppressed.actions == [.cancelReveal(display: left.id, token: token)])

        let exited = BottomDockReducer.reduce(suppressed.model, event: .fullscreenExited(display: left.id))
        let exitToken = exited.model.state(for: left.id)!.generation
        #expect(exited.model.state(for: left.id)?.phase == .revealPending)
        #expect(exited.actions == [.scheduleReveal(display: left.id, token: exitToken, after: 0.2)])
    }

    @Test("removing a display cancels its coordinator work and removes its state")
    func displayRemoval() {
        let visible = revealed()
        let removed = BottomDockReducer.reduce(visible, event: .displayRemoved(left.id))

        #expect(removed.model.state(for: left.id) == nil)
        #expect(removed.model.displays.isEmpty)
        #expect(removed.actions == [.conceal(display: left.id)])
    }

    @Test("removing an adjacent display re-evaluates surviving dock ownership and cancels stale hiding")
    func removalReconcilesSurvivingDisplay() {
        let below = BottomDockDisplay(id: "below", frame: CGRect(x: 0, y: -100, width: 100, height: 100))
        let initial = BottomDockModel(displays: [left], physicalDisplays: [left, below], configuration: configuration)
        let pending = BottomDockReducer.reduce(initial, event: .pointerMoved(CGPoint(x: 50, y: 1)))
        let visible = BottomDockReducer.reduce(pending.model, event: .revealTimerFired(display: left.id, token: pending.model.state(for: left.id)!.generation)).model
        let hiding = BottomDockReducer.reduce(visible, event: .pointerMoved(CGPoint(x: 50, y: -5)))
        let staleHideToken = hiding.model.state(for: left.id)!.generation
        let removed = BottomDockReducer.reduce(hiding.model, event: .displayRemoved(below.id))
        let staleFire = BottomDockReducer.reduce(removed.model, event: .hideTimerFired(display: left.id, token: staleHideToken))

        #expect(removed.model.pointerDisplay == left.id)
        #expect(removed.model.state(for: left.id)?.phase == .revealed)
        #expect(removed.actions == [.cancelHide(display: left.id, token: staleHideToken)])
        #expect(staleFire.model.state(for: left.id)?.phase == .revealed)
        #expect(staleFire.actions.isEmpty)
    }

    @Test("every interaction lease keeps a dock revealed and restarts exit grace when released", arguments: BottomDockLease.allCases)
    func eachLeaseType(lease: BottomDockLease) {
        let visible = revealed()
        let hiding = BottomDockReducer.reduce(visible, event: .pointerMoved(CGPoint(x: 150, y: 50)))
        let hideToken = hiding.model.state(for: left.id)!.generation
        let leased = BottomDockReducer.reduce(hiding.model, event: .interactionLeaseChanged(display: left.id, lease: lease, isActive: true))

        #expect(leased.model.state(for: left.id)?.phase == .revealed)
        #expect(leased.model.state(for: left.id)?.leases == [lease])
        #expect(leased.actions == [.cancelHide(display: left.id, token: hideToken)])

        let released = BottomDockReducer.reduce(leased.model, event: .interactionLeaseChanged(display: left.id, lease: lease, isActive: false))
        let releaseToken = released.model.state(for: left.id)!.generation
        #expect(released.model.state(for: left.id)?.phase == .hidePending)
        #expect(released.actions == [.scheduleHide(display: left.id, token: releaseToken, after: 0.4)])
    }

    @Test("a stale hide timer cannot conceal after the pointer re-enters the keep area")
    func staleHideTimerCancellation() {
        let visible = revealed()
        let hiding = BottomDockReducer.reduce(visible, event: .pointerMoved(CGPoint(x: 150, y: 50)))
        let staleToken = hiding.model.state(for: left.id)!.generation
        let reentered = BottomDockReducer.reduce(hiding.model, event: .pointerMoved(CGPoint(x: 50, y: 10)))
        let staleFire = BottomDockReducer.reduce(reentered.model, event: .hideTimerFired(display: left.id, token: staleToken))

        #expect(reentered.actions == [.cancelHide(display: left.id, token: staleToken)])
        #expect(staleFire.model.state(for: left.id)?.phase == .revealed)
        #expect(staleFire.actions.isEmpty)
    }

    @Test("an explicit close conceals the target display and clears its leases")
    func explicitClose() {
        let visible = revealed()
        let leased = BottomDockReducer.reduce(visible, event: .interactionLeaseChanged(display: left.id, lease: .popout, isActive: true))
        let closed = BottomDockReducer.reduce(leased.model, event: .close(display: left.id))

        #expect(closed.model.state(for: left.id)?.phase == .concealed)
        #expect(closed.model.state(for: left.id)?.leases.isEmpty == true)
        #expect(closed.actions == [.conceal(display: left.id)])
    }

    @Test("close preserves fullscreen suppression until fullscreen exits")
    func closeDuringFullscreenRemainsSuppressed() {
        let pending = BottomDockReducer.reduce(model(), event: .pointerMoved(CGPoint(x: 50, y: -5)))
        let suppressed = BottomDockReducer.reduce(pending.model, event: .fullscreenEntered(display: left.id))
        let closed = BottomDockReducer.reduce(suppressed.model, event: .close(display: left.id))
        let pointerMove = BottomDockReducer.reduce(closed.model, event: .pointerMoved(CGPoint(x: 50, y: -5)))

        #expect(closed.model.state(for: left.id)?.phase == .fullscreenSuppressed)
        #expect(closed.actions.isEmpty)
        #expect(pointerMove.model.state(for: left.id)?.phase == .fullscreenSuppressed)
        #expect(pointerMove.actions.isEmpty)
    }

    @Test("a stale reveal timer cannot apply after pointer cancellation or fullscreen suppression")
    func staleTimerCancellation() {
        let pending = BottomDockReducer.reduce(model(), event: .pointerMoved(CGPoint(x: 50, y: -5)))
        let staleToken = pending.model.state(for: left.id)!.generation
        let cancelled = BottomDockReducer.reduce(pending.model, event: .pointerMoved(CGPoint(x: 50, y: 50)))
        let restarted = BottomDockReducer.reduce(cancelled.model, event: .pointerMoved(CGPoint(x: 50, y: -5)))
        let staleFire = BottomDockReducer.reduce(restarted.model, event: .revealTimerFired(display: left.id, token: staleToken))
        let suppressed = BottomDockReducer.reduce(staleFire.model, event: .fullscreenEntered(display: left.id))
        let fullscreenStaleFire = BottomDockReducer.reduce(suppressed.model, event: .revealTimerFired(display: left.id, token: staleToken))

        #expect(cancelled.actions == [.cancelReveal(display: left.id, token: staleToken)])
        #expect(staleFire.model.state(for: left.id)?.phase == .revealPending)
        #expect(staleFire.actions.isEmpty)
        #expect(fullscreenStaleFire.model.state(for: left.id)?.phase == .fullscreenSuppressed)
        #expect(fullscreenStaleFire.actions.isEmpty)
    }
}
