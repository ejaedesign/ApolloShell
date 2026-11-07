import CoreGraphics
import Testing
@testable import ApolloShell
@testable import ApolloShellCore

@Suite("Bottom dock app trigger policy")
struct BottomDockTriggerPolicyTests {
    @Test("utilities hover strip keeps bottom-right trigger priority")
    func utilitiesHoverStripIsExcluded() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let utilities = CGRect(x: 985, y: -2, width: 443, height: 4)

        #expect(BottomDockTriggerPolicy.excludesTrigger(
            CGPoint(x: 1200, y: 1), screen: screen, utilitiesTrigger: utilities
        ))
        #expect(!BottomDockTriggerPolicy.excludesTrigger(
            CGPoint(x: 800, y: 1), screen: screen, utilitiesTrigger: utilities
        ))
        #expect(!BottomDockTriggerPolicy.excludesTrigger(
            CGPoint(x: 1200, y: 10), screen: screen, utilitiesTrigger: utilities
        ))
    }

    @Test("timer routing keeps display identity and generation token")
    func timerRoutingPreservesGeneration() {
        let id: BottomDockDisplayID = "display-4"
        #expect(BottomDockTimerRoute.reveal.event(display: id, token: 9) == .revealTimerFired(display: id, token: 9))
        #expect(BottomDockTimerRoute.hide.event(display: id, token: 10) == .hideTimerFired(display: id, token: 10))
    }
}
