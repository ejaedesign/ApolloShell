import CoreGraphics
import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Untere Leiste: Core-Geometrie")
struct BottomDockGeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test("fehlende oder ungueltige Position bleibt links, unten wird gelesen")
    func tolerantPlacementDecoding() throws {
        let missing = try JSONDecoder().decode(ShellSettings.Bar.self, from: Data(#"{}"#.utf8))
        let invalid = try JSONDecoder().decode(ShellSettings.Bar.self, from: Data(#"{"side":"top"}"#.utf8))
        let malformed = try JSONDecoder().decode(ShellSettings.Bar.self, from: Data(#"{"side":17}"#.utf8))
        let bottom = try JSONDecoder().decode(ShellSettings.Bar.self, from: Data(#"{"side":"bottom"}"#.utf8))

        #expect(missing.side == .left)
        #expect(invalid.side == .left)
        #expect(malformed.side == .left)
        #expect(bottom.side == .bottom)
        #expect(try JSONDecoder().decode(ShellSettings.Bar.self, from: JSONEncoder().encode(bottom)).side == .bottom)
    }

    @Test("unten ist waagerecht und belegt die untere Bildschirmkante")
    func bottomPlacementOrientation() {
        #expect(BarSide.bottom.axis == .horizontal)
        #expect(BarSide.bottom.screenEdge == .bottom)
        #expect(BarSide.left.axis == .vertical)
        #expect(BarSide.right.axis == .vertical)
    }

    @Test("unteres Panel ist bildschirmbreit und enthaelt nur unteren Ueberstand")
    func bottomPanelFrame() {
        let frame = BarPanelGeometry.frame(screen: screen, visibleTop: 958, thickness: 44,
                                           edgeBleed: 0, bottomBleed: SidebarBleed.depth, expandedWidth: 300, side: .bottom)

        #expect(frame == CGRect(x: 0, y: -SidebarBleed.depth, width: 1512, height: 44 + SidebarBleed.depth))
    }

    @Test("nur unten verwendet die horizontale Dock-Inhaltsroute und unterdrueckt Seitenpopouts")
    func bottomContentRoute() {
        #expect(BarSide.bottom.contentRoute == .dock)
        #expect(BarSide.bottom.allowsSidePopouts == false)
        #expect(BarSide.left.contentRoute == .sidebar)
        #expect(BarSide.right.contentRoute == .sidebar)
        #expect(BarSide.left.allowsSidePopouts)
        #expect(BarSide.right.allowsSidePopouts)
    }

    @Test("untere Leiste blutet nur unten ueber einen freien Rand")
    func bottomBleed() {
        let free = SidebarBleed.edges(screen: screen, others: [screen], side: .bottom)
        let neighbourBelow = CGRect(x: 100, y: -1080, width: 1920, height: 1080)
        let blocked = SidebarBleed.edges(screen: screen, others: [screen, neighbourBelow], side: .bottom)
        let neighbourAtSide = CGRect(x: screen.maxX, y: 0, width: 1920, height: 1080)
        let sideIsFree = SidebarBleed.edges(screen: screen, others: [screen, neighbourAtSide], side: .bottom)

        #expect(free.left == 0)
        #expect(free.bottom == SidebarBleed.depth)
        #expect(blocked.left == 0)
        #expect(blocked.bottom == 0)
        #expect(sideIsFree.left == 0)
        #expect(sideIsFree.bottom == SidebarBleed.depth)
    }

    @Test("untere Leiste kuerzt angeheftete Fenster nach oben")
    func bottomClamp() {
        let filled = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let result = WindowClamp.clampedFrame(window: filled, screen: screen, reservedWidth: 44, side: .bottom)

        #expect(result == CGRect(x: 0, y: 0, width: 1512, height: 938))
    }

    @Test("untere Leiste verschiebt freie Fenster nach oben")
    func bottomClampMovesWindowUpward() {
        let overlapping = CGRect(x: 100, y: 700, width: 500, height: 300)

        #expect(WindowClamp.clampedFrame(window: overlapping, screen: screen, reservedWidth: 44, side: .bottom)
            == CGRect(x: 100, y: 638, width: 500, height: 300))
    }

    @Test("untere Leiste verwendet AX-y auf einem versetzten Bildschirm")
    func bottomClampOnOffsetScreen() {
        let offset = CGRect(x: 1512, y: 982, width: 1920, height: 1080)
        let filled = CGRect(x: 1512, y: 982, width: 1920, height: 1080)

        #expect(WindowClamp.clampedFrame(window: filled, screen: offset, reservedWidth: 44, side: .bottom)
            == CGRect(x: 1512, y: 982, width: 1920, height: 1036))
    }
}