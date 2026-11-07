import CoreGraphics

/// Reine Platzierung der Desktop-Uhr. Die Fensterklasse misst nur noch die
/// SwiftUI-Ansicht und wendet diesen Rahmen an.
public enum DesktopClockLayout {
    public static func frame(
        visibleFrame: CGRect,
        clockSize: CGSize,
        margin: CGFloat,
        shadowInset: CGFloat,
        dockThickness: CGFloat,
        side: BarSide
    ) -> CGRect {
        let inset = margin - shadowInset
        let dockOffset = side.contentRoute == .dock ? max(0, dockThickness) : 0
        return CGRect(
            x: side == .right ? visibleFrame.minX + inset : visibleFrame.maxX - clockSize.width - inset,
            y: visibleFrame.minY + inset + dockOffset,
            width: clockSize.width,
            height: clockSize.height
        )
    }
}
