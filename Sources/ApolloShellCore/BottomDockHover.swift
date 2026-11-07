import CoreGraphics
import Foundation

/// Stable identity for a selected display that owns a bottom dock.
public struct BottomDockDisplayID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String { rawValue }
}

/// A display expressed without AppKit so hover ownership can be tested in Core.
public struct BottomDockDisplay: Equatable, Sendable, Identifiable {
    public let id: BottomDockDisplayID
    public let frame: CGRect
    /// `nil` uses the model default. A display with blocked exterior space can
    /// set this to zero without changing other selected displays.
    public let bottomBleed: CGFloat?

    public init(id: BottomDockDisplayID, frame: CGRect, bottomBleed: CGFloat? = nil) {
        self.id = id
        self.frame = frame
        self.bottomBleed = bottomBleed.map { max(0, $0) }
    }
}

/// Timing values forwarded to the application coordinator with timer actions.
public struct BottomDockTiming: Equatable, Sendable {
    public let revealDwell: TimeInterval
    public let hideGrace: TimeInterval

    public init(revealDwell: TimeInterval, hideGrace: TimeInterval) {
        self.revealDwell = revealDwell
        self.hideGrace = hideGrace
    }
}

/// Immutable geometry and timing configuration shared by all selected displays.
public struct BottomDockConfiguration: Equatable, Sendable {
    public let dockThickness: CGFloat
    public let bottomBleed: CGFloat
    public let timing: BottomDockTiming

    public init(dockThickness: CGFloat, bottomBleed: CGFloat, timing: BottomDockTiming) {
        self.dockThickness = max(0, dockThickness)
        self.bottomBleed = max(0, bottomBleed)
        self.timing = timing
    }
}

public enum BottomDockGeometry {
    /// The interior edge trigger is deliberately narrow when another display
    /// prevents a usable strip outside this display's bottom edge.
    public static let interiorTriggerThickness: CGFloat = 2

    public struct Areas: Equatable, Sendable {
        public let trigger: CGRect
        public let keep: CGRect
        public let usesExteriorTrigger: Bool

        public init(trigger: CGRect, keep: CGRect, usesExteriorTrigger: Bool) {
            self.trigger = trigger
            self.keep = keep
            self.usesExteriorTrigger = usesExteriorTrigger
        }
    }

    /// Returns only a display whose frame literally contains the point. Gaps
    /// remain unowned rather than being assigned to a nearest display.
    public static func displayOwning(_ point: CGPoint, among displays: [BottomDockDisplay]) -> BottomDockDisplayID? {
        displays.first(where: { $0.frame.contains(point) })?.id
    }

    /// Uses the requested exterior strip only when no other selected display
    /// occupies it. This is deliberately computed per display: a lower
    /// neighbour may block one dock while another display can still bleed.
    public static func availableBottomBleed(
        for display: BottomDockDisplay,
        among displays: [BottomDockDisplay],
        requested: CGFloat
    ) -> CGFloat {
        let bleed = max(0, requested)
        guard bleed > 0 else { return 0 }
        let exterior = CGRect(
            x: display.frame.minX,
            y: display.frame.minY - bleed,
            width: display.frame.width,
            height: bleed
        )
        return displays.contains { $0.id != display.id && $0.frame.intersects(exterior) } ? 0 : bleed
    }

    /// Builds the hidden trigger and visible keep area for one bottom dock.
    /// Coordinates use an upward-y desktop space: a display's bottom edge is
    /// its frame's minimum y.
    /// An available exterior strip becomes part of both areas so a pointer can
    /// dwell below the display edge without cancelling its pending reveal.
    public static func areas(for display: BottomDockDisplay, dockThickness: CGFloat, bottomBleed: CGFloat) -> Areas {
        let thickness = max(0, dockThickness)
        let bleed = max(0, bottomBleed)
        let frame = display.frame
        let interiorDepth = min(thickness, interiorTriggerThickness)
        if bleed > 0 {
            return Areas(
                trigger: CGRect(
                    x: frame.minX,
                    y: frame.minY - bleed,
                    width: frame.width,
                    height: bleed + interiorDepth
                ),
                keep: CGRect(
                    x: frame.minX,
                    y: frame.minY - bleed,
                    width: frame.width,
                    height: thickness + bleed
                ),
                usesExteriorTrigger: true
            )
        }
        let triggerDepth = min(thickness, interiorTriggerThickness)
        return Areas(
            trigger: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: triggerDepth),
            keep: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: thickness),
            usesExteriorTrigger: false
        )
    }
}

public enum BottomDockPhase: Equatable, Sendable {
    case concealed
    case revealPending
    case revealed
    case hidePending
    case fullscreenSuppressed
}

/// A coordinator-held lease that prevents a dock from concealing mid-interaction.
public enum BottomDockLease: CaseIterable, Hashable, Sendable {
    case mouseDownDrag
    case nativeMenu
    case fileDragDrop
    case popout
}

/// Per-display state, including the generation that validates asynchronous timers.
public struct BottomDockDisplayState: Equatable, Sendable {
    public let displayID: BottomDockDisplayID
    public internal(set) var phase: BottomDockPhase
    public internal(set) var generation: UInt64
    public internal(set) var leases: Set<BottomDockLease>

    public init(
        displayID: BottomDockDisplayID,
        phase: BottomDockPhase = .concealed,
        generation: UInt64 = 0,
        leases: Set<BottomDockLease> = []
    ) {
        self.displayID = displayID
        self.phase = phase
        self.generation = generation
        self.leases = leases
    }
}

/// Complete, pure state for every selected display.
public struct BottomDockModel: Equatable, Sendable {
    public internal(set) var displays: [BottomDockDisplayID: BottomDockDisplay]
    /// All physical displays, including those without a selected dock. They
    /// determine boundary ownership and whether exterior bleed is blocked.
    public internal(set) var physicalDisplays: [BottomDockDisplay]
    public internal(set) var states: [BottomDockDisplayID: BottomDockDisplayState]
    public internal(set) var displayOrder: [BottomDockDisplayID]
    public internal(set) var pointer: CGPoint?
    public internal(set) var pointerDisplay: BottomDockDisplayID?
    public let configuration: BottomDockConfiguration

    public init(
        displays: [BottomDockDisplay],
        physicalDisplays: [BottomDockDisplay]? = nil,
        configuration: BottomDockConfiguration
    ) {
        let physicalDisplays = physicalDisplays ?? displays
        precondition(Set(displays.map(\.id)).count == displays.count, "Bottom dock displays require unique identities")
        precondition(Set(physicalDisplays.map(\.id)).count == physicalDisplays.count, "Physical displays require unique identities")
        precondition(Set(displays.map(\.id)).isSubset(of: Set(physicalDisplays.map(\.id))), "Selected docks require physical displays")
        self.displays = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
        self.physicalDisplays = physicalDisplays
        self.states = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, BottomDockDisplayState(displayID: $0.id)) })
        self.displayOrder = displays.map(\.id)
        self.pointer = nil
        self.pointerDisplay = nil
        self.configuration = configuration
    }

    public func state(for display: BottomDockDisplayID) -> BottomDockDisplayState? {
        states[display]
    }
}

public enum BottomDockEvent: Equatable, Sendable {
    case pointerMoved(CGPoint)
    case pointerLeft
    case revealTimerFired(display: BottomDockDisplayID, token: UInt64)
    case hideTimerFired(display: BottomDockDisplayID, token: UInt64)
    case fullscreenEntered(display: BottomDockDisplayID)
    case fullscreenExited(display: BottomDockDisplayID)
    case displayRemoved(BottomDockDisplayID)
    case interactionLeaseChanged(display: BottomDockDisplayID, lease: BottomDockLease, isActive: Bool)
    case close(display: BottomDockDisplayID)
}

/// Explicit work for the AppKit coordinator. Core neither creates timers nor changes windows.
public enum BottomDockAction: Equatable, Sendable {
    case scheduleReveal(display: BottomDockDisplayID, token: UInt64, after: TimeInterval)
    case cancelReveal(display: BottomDockDisplayID, token: UInt64)
    case scheduleHide(display: BottomDockDisplayID, token: UInt64, after: TimeInterval)
    case cancelHide(display: BottomDockDisplayID, token: UInt64)
    case reveal(display: BottomDockDisplayID)
    case conceal(display: BottomDockDisplayID)
}

public struct BottomDockReduction: Equatable, Sendable {
    public let model: BottomDockModel
    public let actions: [BottomDockAction]

    public init(model: BottomDockModel, actions: [BottomDockAction]) {
        self.model = model
        self.actions = actions
    }
}

public enum BottomDockReducer {
    public static func reduce(_ model: BottomDockModel, event: BottomDockEvent) -> BottomDockReduction {
        var model = model
        var actions: [BottomDockAction] = []

        switch event {
        case .pointerMoved(let point):
            model.pointer = point
            model.pointerDisplay = dockOwning(point, in: model)
            reconcilePointer(in: &model, actions: &actions)

        case .pointerLeft:
            model.pointer = nil
            model.pointerDisplay = nil
            for id in model.displayOrder {
                guard var state = model.states[id] else { continue }
                updatePointer(
                    state: &state,
                    display: id,
                    inTrigger: false,
                    inKeep: false,
                    timing: model.configuration.timing,
                    actions: &actions
                )
                model.states[id] = state
            }

        case .revealTimerFired(let id, let token):
            guard var state = model.states[id], state.phase == .revealPending, state.generation == token else { break }
            state.phase = .revealed
            model.states[id] = state
            actions.append(.reveal(display: id))

        case .hideTimerFired(let id, let token):
            guard var state = model.states[id], state.phase == .hidePending, state.generation == token else { break }
            state.phase = .concealed
            model.states[id] = state
            actions.append(.conceal(display: id))

        case .fullscreenEntered(let id):
            guard var state = model.states[id], state.phase != .fullscreenSuppressed else { break }
            let wasVisible = state.phase == .revealed || state.phase == .hidePending
            cancelPending(state: &state, display: id, actions: &actions)
            state.generation &+= 1
            state.phase = .fullscreenSuppressed
            model.states[id] = state
            if wasVisible {
                actions.append(.conceal(display: id))
            }

        case .fullscreenExited(let id):
            guard var state = model.states[id], state.phase == .fullscreenSuppressed else { break }
            state.generation &+= 1
            state.phase = .concealed
            if !state.leases.isEmpty {
                state.phase = .revealed
                actions.append(.reveal(display: id))
            } else if let point = model.pointer, model.pointerDisplay == id, let display = model.displays[id] {
                let displayAreas = areas(for: display, in: model)
                updatePointer(
                    state: &state,
                    display: id,
                    inTrigger: displayAreas.trigger.contains(point),
                    inKeep: displayAreas.keep.contains(point),
                    timing: model.configuration.timing,
                    actions: &actions
                )
            }
            model.states[id] = state

        case .displayRemoved(let id):
            if var state = model.states[id] {
                let wasVisible = state.phase == .revealed || state.phase == .hidePending
                cancelPending(state: &state, display: id, actions: &actions)
                if wasVisible {
                    actions.append(.conceal(display: id))
                }
                model.states.removeValue(forKey: id)
                model.displays.removeValue(forKey: id)
                model.displayOrder.removeAll { $0 == id }
            }
            model.physicalDisplays.removeAll { $0.id == id }
            if let point = model.pointer {
                model.pointerDisplay = dockOwning(point, in: model)
                reconcilePointer(in: &model, actions: &actions)
            } else {
                model.pointerDisplay = nil
            }

        case .interactionLeaseChanged(let id, let lease, let isActive):
            guard var state = model.states[id] else { break }
            if state.phase == .fullscreenSuppressed {
                if isActive {
                    state.leases.insert(lease)
                } else {
                    state.leases.remove(lease)
                }
                model.states[id] = state
                break
            }
            if isActive {
                let inserted = state.leases.insert(lease).inserted
                guard inserted else { break }
                switch state.phase {
                case .hidePending:
                    cancelHide(state: &state, display: id, actions: &actions)
                    state.phase = .revealed
                case .revealPending:
                    cancelReveal(state: &state, display: id, actions: &actions)
                    state.phase = .revealed
                    actions.append(.reveal(display: id))
                case .concealed:
                    state.phase = .revealed
                    actions.append(.reveal(display: id))
                case .revealed, .fullscreenSuppressed:
                    break
                }
            } else {
                guard state.leases.remove(lease) != nil else { break }
                if state.leases.isEmpty, state.phase == .revealed, !pointerIsInKeepArea(for: id, model: model) {
                    beginHide(state: &state, display: id, timing: model.configuration.timing, actions: &actions)
                }
            }
            model.states[id] = state

        case .close(let id):
            guard var state = model.states[id] else { break }
            if state.phase == .fullscreenSuppressed {
                state.generation &+= 1
                state.leases.removeAll()
                model.states[id] = state
                break
            }
            let wasVisible = state.phase == .revealed || state.phase == .hidePending
            cancelPending(state: &state, display: id, actions: &actions)
            state.generation &+= 1
            state.leases.removeAll()
            state.phase = .concealed
            model.states[id] = state
            if wasVisible {
                actions.append(.conceal(display: id))
            }
        }

        return BottomDockReduction(model: model, actions: actions)
    }

    private static func orderedDisplays(in model: BottomDockModel) -> [BottomDockDisplay] {
        model.displayOrder.compactMap { model.displays[$0] }
    }

    private static func reconcilePointer(in model: inout BottomDockModel, actions: inout [BottomDockAction]) {
        guard let point = model.pointer else { return }
        for id in model.displayOrder {
            guard var state = model.states[id], let display = model.displays[id] else { continue }
            let areas = areas(for: display, in: model)
            let ownsPointer = model.pointerDisplay == id
            updatePointer(
                state: &state,
                display: id,
                inTrigger: ownsPointer && areas.trigger.contains(point),
                inKeep: ownsPointer && areas.keep.contains(point),
                timing: model.configuration.timing,
                actions: &actions
            )
            model.states[id] = state
        }
    }

    /// Physical screen ownership wins. Only points in no physical display may
    /// be assigned to a selected dock's confirmed exterior bleed area.
    private static func dockOwning(_ point: CGPoint, in model: BottomDockModel) -> BottomDockDisplayID? {
        if let physicalOwner = BottomDockGeometry.displayOwning(point, among: model.physicalDisplays) {
            return model.displays[physicalOwner] == nil ? nil : physicalOwner
        }
        return orderedDisplays(in: model).first { areas(for: $0, in: model).keep.contains(point) }?.id
    }

    private static func areas(for display: BottomDockDisplay, in model: BottomDockModel) -> BottomDockGeometry.Areas {
        let requestedBleed = display.bottomBleed ?? model.configuration.bottomBleed
        let bleed = BottomDockGeometry.availableBottomBleed(
            for: display,
            among: model.physicalDisplays,
            requested: requestedBleed
        )
        return BottomDockGeometry.areas(
            for: display,
            dockThickness: model.configuration.dockThickness,
            bottomBleed: bleed
        )
    }

    private static func updatePointer(
        state: inout BottomDockDisplayState,
        display: BottomDockDisplayID,
        inTrigger: Bool,
        inKeep: Bool,
        timing: BottomDockTiming,
        actions: inout [BottomDockAction]
    ) {
        guard state.phase != .fullscreenSuppressed else { return }
        switch state.phase {
        case .concealed:
            if inTrigger { beginReveal(state: &state, display: display, timing: timing, actions: &actions) }
        case .revealPending:
            if !inTrigger && !inKeep { cancelReveal(state: &state, display: display, actions: &actions); state.phase = .concealed }
        case .revealed:
            if !inKeep && state.leases.isEmpty { beginHide(state: &state, display: display, timing: timing, actions: &actions) }
        case .hidePending:
            if inKeep || !state.leases.isEmpty { cancelHide(state: &state, display: display, actions: &actions); state.phase = .revealed }
        case .fullscreenSuppressed:
            break
        }
    }

    private static func pointerIsInKeepArea(for id: BottomDockDisplayID, model: BottomDockModel) -> Bool {
        guard
            let point = model.pointer,
            model.pointerDisplay == id,
            let display = model.displays[id]
        else { return false }
        return areas(for: display, in: model).keep.contains(point)
    }

    private static func beginReveal(
        state: inout BottomDockDisplayState,
        display: BottomDockDisplayID,
        timing: BottomDockTiming,
        actions: inout [BottomDockAction]
    ) {
        state.generation &+= 1
        state.phase = .revealPending
        actions.append(.scheduleReveal(display: display, token: state.generation, after: timing.revealDwell))
    }

    private static func beginHide(
        state: inout BottomDockDisplayState,
        display: BottomDockDisplayID,
        timing: BottomDockTiming,
        actions: inout [BottomDockAction]
    ) {
        state.generation &+= 1
        state.phase = .hidePending
        actions.append(.scheduleHide(display: display, token: state.generation, after: timing.hideGrace))
    }

    private static func cancelPending(
        state: inout BottomDockDisplayState,
        display: BottomDockDisplayID,
        actions: inout [BottomDockAction]
    ) {
        switch state.phase {
        case .revealPending:
            cancelReveal(state: &state, display: display, actions: &actions)
        case .hidePending:
            cancelHide(state: &state, display: display, actions: &actions)
        case .concealed, .revealed, .fullscreenSuppressed:
            break
        }
    }

    private static func cancelReveal(
        state: inout BottomDockDisplayState,
        display: BottomDockDisplayID,
        actions: inout [BottomDockAction]
    ) {
        actions.append(.cancelReveal(display: display, token: state.generation))
        state.generation &+= 1
    }

    private static func cancelHide(
        state: inout BottomDockDisplayState,
        display: BottomDockDisplayID,
        actions: inout [BottomDockAction]
    ) {
        actions.append(.cancelHide(display: display, token: state.generation))
        state.generation &+= 1
    }
}
