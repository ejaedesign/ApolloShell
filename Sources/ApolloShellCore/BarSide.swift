import CoreGraphics

/// Richtung, in der eine Leiste entlang der Bildschirmkante laeuft.
public enum BarPlacementAxis: Equatable, Sendable {
    case vertical, horizontal
}

/// The SwiftUI route rendered for a placement. Bottom is deliberately a dock,
/// not a rotated sidebar with modules that only understand vertical anchors.
public enum BarContentRoute: Equatable, Sendable {
    case sidebar, dock
}

/// Bildschirmkante, die eine Leiste belegt.
public enum BarScreenEdge: Equatable, Sendable {
    case left, right, bottom

    /// Streifen unmittelbar ausserhalb dieser Kante in AppKit-Koordinaten.
    public func exteriorStrip(of screen: CGRect, depth: CGFloat) -> CGRect {
        switch self {
        case .left:
            CGRect(x: screen.minX - depth, y: screen.minY, width: depth, height: screen.height)
        case .right:
            CGRect(x: screen.maxX, y: screen.minY, width: depth, height: screen.height)
        case .bottom:
            CGRect(x: screen.minX, y: screen.minY - depth, width: screen.width, height: depth)
        }
    }
}

/// Geometrie einer Leistenposition. Sie bildet jede belegte Kante auf die
/// linke Kante eines kanonischen Rechtecks ab, damit Kernberechnungen nicht
/// fuer jede Kante eigene Zweige brauchen.
public struct BarPlacementGeometry: Sendable {
    public let axis: BarPlacementAxis
    public let screenEdge: BarScreenEdge

    public init(axis: BarPlacementAxis, screenEdge: BarScreenEdge) {
        self.axis = axis
        self.screenEdge = screenEdge
    }

    public func canonicalized(_ rect: CGRect, in screen: CGRect) -> CGRect {
        switch screenEdge {
        case .left:
            rect
        case .right:
            BarSide.mirrored(rect, in: screen)
        case .bottom:
            CGRect(
                x: screen.minY + screen.maxY - rect.maxY,
                y: rect.minX,
                width: rect.height,
                height: rect.width
            )
        }
    }

    public func decanonicalized(_ rect: CGRect, in screen: CGRect) -> CGRect {
        switch screenEdge {
        case .left:
            return rect
        case .right:
            return BarSide.mirrored(rect, in: screen)
        case .bottom:
            let maxY = screen.minY + screen.maxY - rect.minX
            return CGRect(x: rect.minY, y: maxY - rect.width, width: rect.height, height: rect.width)
        }
    }
}

/// Kante, an der die Leiste steht (Nexus > Leiste > Position).
public enum BarSide: String, Codable, CaseIterable, Sendable {
    case left, right, bottom

    public var geometry: BarPlacementGeometry {
        switch self {
        case .left: BarPlacementGeometry(axis: .vertical, screenEdge: .left)
        case .right: BarPlacementGeometry(axis: .vertical, screenEdge: .right)
        case .bottom: BarPlacementGeometry(axis: .horizontal, screenEdge: .bottom)
        }
    }

    public var axis: BarPlacementAxis { geometry.axis }
    public var screenEdge: BarScreenEdge { geometry.screenEdge }
    public var contentRoute: BarContentRoute { axis == .horizontal ? .dock : .sidebar }
    /// Side popouts have no horizontal anchor yet. The dock remains usable;
    /// stack triggers are disabled until the dedicated bottom popout lands.
    public var allowsSidePopouts: Bool { contentRoute == .sidebar }

    /// `rect` an der senkrechten Mittellinie von `bounds` gespiegelt. Ihre
    /// eigene Umkehrung.
    public static func mirrored(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + bounds.maxX - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    }
}

/// AppKit panel geometry for every persisted bar placement. The bottom route
/// is intentionally independent from the vertical side-panel expansion.
public enum BarPanelGeometry {
    public static func frame(
        screen: CGRect,
        visibleTop: CGFloat,
        thickness: CGFloat,
        edgeBleed: CGFloat,
        bottomBleed: CGFloat,
        expandedWidth: CGFloat,
        side: BarSide
    ) -> CGRect {
        let thickness = max(0, thickness)
        let edgeBleed = max(0, edgeBleed)
        let bottomBleed = max(0, bottomBleed)
        if side.contentRoute == .dock {
            return CGRect(x: screen.minX, y: screen.minY - bottomBleed,
                          width: screen.width, height: thickness + bottomBleed)
        }
        var rect = CGRect(x: screen.minX - edgeBleed, y: screen.minY - bottomBleed,
                          width: max(0, expandedWidth) + edgeBleed,
                          height: max(0, visibleTop - screen.minY) + bottomBleed)
        if side == .right { rect = BarSide.mirrored(rect, in: screen) }
        return rect
    }
}
