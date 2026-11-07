import CoreGraphics

/// Richtung, in der eine Leiste entlang der Bildschirmkante laeuft.
public enum BarPlacementAxis: Equatable, Sendable {
    case vertical, horizontal
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

    /// `rect` an der senkrechten Mittellinie von `bounds` gespiegelt. Ihre
    /// eigene Umkehrung.
    public static func mirrored(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + bounds.maxX - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    }
}
