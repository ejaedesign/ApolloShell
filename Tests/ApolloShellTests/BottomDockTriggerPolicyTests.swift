import CoreGraphics
import Testing
@testable import ApolloShell
@testable import ApolloShellCore

@Suite("Bottom dock app trigger policy")
struct BottomDockTriggerPolicyTests {
    @Test("utilities hover strip keeps bottom-right trigger priority")
    func utilitiesHoverStripIsExcluded() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let utilities = EdgeHoverArea.bottomRight(
            screen: screen, width: UtilitiesView.width, height: 0, margin: 25, open: false
        )
        let exterior = CGPoint(x: utilities.midX, y: screen.minY - 1)
        let interior = CGPoint(x: utilities.midX, y: screen.minY + 1)

        #expect(BottomDockTriggerPolicy.excludesTrigger(
            exterior, screen: screen, utilitiesTrigger: utilities
        ))
        #expect(BottomDockTriggerPolicy.excludesTrigger(
            interior, screen: screen, utilitiesTrigger: utilities
        ))
        #expect(!BottomDockTriggerPolicy.excludesTrigger(
            CGPoint(x: utilities.minX - 1, y: screen.minY + 1), screen: screen, utilitiesTrigger: utilities
        ))
        #expect(!BottomDockTriggerPolicy.excludesTrigger(
            CGPoint(x: utilities.midX, y: screen.minY + 10), screen: screen, utilitiesTrigger: utilities
        ))
    }

    @Test("concealed bottom dock remains hidden after its arrival decision")
    func concealedBottomDockDoesNotArriveVisible() {
        #expect(!SidebarScreenVisibility.shouldAppearAfterArrival(
            isHiddenForFullscreen: false, isConcealedForBottomDock: true
        ))
        #expect(SidebarScreenVisibility.shouldIgnoreMouseEvents(
            isHiddenForFullscreen: false, isConcealedForBottomDock: true
        ))
        #expect(SidebarScreenVisibility.shouldAppearAfterArrival(
            isHiddenForFullscreen: false, isConcealedForBottomDock: false
        ))
    }

    @Test("native menu leases bracket tracking without affecting non-bottom menus")
    func nativeMenuLeaseBracketsTracking() {
        var changes: [(BottomDockLease, Bool)] = []
        BottomDockMenuLease.track({ lease, active in
            changes.append((lease, active))
        }) {
            #expect(changes.map(\.1) == [true])
        }
        #expect(changes.map(\.0) == [.nativeMenu, .nativeMenu])
        #expect(changes.map(\.1) == [true, false])

        var normalMenuTrackingCount = 0
        BottomDockMenuLease.track(nil) {
            normalMenuTrackingCount += 1
        }
        #expect(normalMenuTrackingCount == 1)
        #expect(changes.map(\.1) == [true, false])
    }

    @Test("timer routing keeps display identity and generation token")
    func timerRoutingPreservesGeneration() {
        let id: BottomDockDisplayID = "display-4"
        #expect(BottomDockTimerRoute.reveal.event(display: id, token: 9) == .revealTimerFired(display: id, token: 9))
        #expect(BottomDockTimerRoute.hide.event(display: id, token: 10) == .hideTimerFired(display: id, token: 10))
    }
}
