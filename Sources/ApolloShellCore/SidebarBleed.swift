import CoreGraphics

public enum SidebarBleed {
    public static let depth: CGFloat = 30

    public static func edges(screen: CGRect, others: [CGRect], side: BarSide = .left,
                             depth: CGFloat = depth) -> (left: CGFloat, bottom: CGFloat) {
        let rest = others.filter { $0 != screen }
        func free(_ r: CGRect) -> Bool { !rest.contains { $0.intersects(r) } }

        let geometry = side.geometry
        let left = geometry.axis == .vertical && free(geometry.screenEdge.exteriorStrip(of: screen, depth: depth)) ? depth : 0
        let belowX = geometry.screenEdge == .left ? screen.minX - left : screen.minX
        let belowWidth = screen.width + left
        let below = CGRect(x: belowX, y: screen.minY - depth, width: belowWidth, height: depth)
        return (left, free(below) ? depth : 0)
    }
}
