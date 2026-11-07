import ApolloShellCore
import CoreGraphics
import Testing

@Suite("Unteres Dock: erreichbare Gruppen und Desktop-Uhr")
struct BottomDockPresentationTests {
    private let apps = [
        DockSlot(bundleID: "dev.editor", pinned: true, running: true),
        DockSlot(bundleID: "dev.terminal", pinned: false, running: false),
    ]

    private var group: DockItem {
        .group(DockGroup(key: "dev", title: "Developer", symbol: "hammer", members: apps))
    }

    @Test("unten entfaltet Gruppen in ihre normalen App-Elemente")
    func bottomExpandsGroupsIntoInteractiveApps() {
        let items = DockItemPresentation.items([group], for: .bottom)

        #expect(items == apps.map(DockItem.app))
    }

    @Test("seitliche Leisten behalten Gruppen als Stack-Ausloeser")
    func sidebarsRetainGroups() {
        #expect(DockItemPresentation.items([group], for: .left) == [group])
        #expect(DockItemPresentation.items([group], for: .right) == [group])
    }

    @Test("untere Leiste setzt die Desktop-Uhr ueber ihre Hoehe")
    func bottomClockSitsAboveDockThickness() {
        let visible = CGRect(x: 100, y: 20, width: 1200, height: 800)
        let size = CGSize(width: 200, height: 80)

        let frame = DesktopClockLayout.frame(
            visibleFrame: visible,
            clockSize: size,
            margin: 32,
            shadowInset: 24,
            dockThickness: 44,
            side: .bottom
        )

        #expect(frame == CGRect(x: 1092, y: 72, width: 200, height: 80))
    }

    @Test("seitliche Leisten behalten die bisherige Uhr-Position")
    func sideClockPlacementIsUnchanged() {
        let visible = CGRect(x: 100, y: 20, width: 1200, height: 800)
        let size = CGSize(width: 200, height: 80)

        let left = DesktopClockLayout.frame(
            visibleFrame: visible,
            clockSize: size,
            margin: 32,
            shadowInset: 24,
            dockThickness: 44,
            side: .left
        )
        let right = DesktopClockLayout.frame(
            visibleFrame: visible,
            clockSize: size,
            margin: 32,
            shadowInset: 24,
            dockThickness: 44,
            side: .right
        )

        #expect(left == CGRect(x: 1092, y: 28, width: 200, height: 80))
        #expect(right == CGRect(x: 108, y: 28, width: 200, height: 80))
    }
}
