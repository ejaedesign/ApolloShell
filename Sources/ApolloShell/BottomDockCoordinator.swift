import AppKit
import ApolloShellCore
import CoreGraphics
import SwiftUI

/// App-layer priority rule: Utilities owns its existing lower-right edge strip
/// before a concealed bottom dock can begin its reveal dwell.
enum BottomDockTriggerPolicy {
    static func excludesTrigger(_ point: CGPoint, screen _: CGRect, utilitiesTrigger: CGRect) -> Bool {
        utilitiesTrigger.contains(point)
    }
}

/// Testable bridge from an AppKit timer callback to Core's token-checked event.
enum BottomDockTimerRoute {
    case reveal, hide

    func event(display: BottomDockDisplayID, token: UInt64) -> BottomDockEvent {
        switch self {
        case .reveal: .revealTimerFired(display: display, token: token)
        case .hide: .hideTimerFired(display: display, token: token)
        }
    }
}

@MainActor
final class BottomDockInteraction {
    var leaseChanged: (BottomDockLease, Bool) -> Void = { _, _ in }
}

/// Keeps a bottom dock visible for the exact synchronous AppKit menu-tracking
/// interval. A nil callback is the normal sidebar/launcher path and is a no-op.
enum BottomDockMenuLease {
    static func track(_ leaseChanged: ((BottomDockLease, Bool) -> Void)?, _ tracking: () -> Void) {
        leaseChanged?(.nativeMenu, true)
        defer { leaseChanged?(.nativeMenu, false) }
        tracking()
    }
}

private struct BottomDockInteractionKey: EnvironmentKey {
    static let defaultValue: BottomDockInteraction? = nil
}

extension EnvironmentValues {
    var bottomDockInteraction: BottomDockInteraction? {
        get { self[BottomDockInteractionKey.self] }
        set { self[BottomDockInteractionKey.self] = newValue }
    }
}

/// AppKit adapter for the tested Core reducer. It owns monitors and timers;
/// all visibility transitions and generation validation remain in Core.
@MainActor
final class BottomDockCoordinator {
    private enum TimerKind: Hashable { case reveal, hide }
    private struct TimerKey: Hashable {
        let display: BottomDockDisplayID
        let kind: TimerKind
    }

    private var model: BottomDockModel?
    private var physicalFrames: [BottomDockDisplayID: CGRect] = [:]
    private var displayIDs: [BottomDockDisplayID: CGDirectDisplayID] = [:]
    private var timers: [TimerKey: DispatchWorkItem] = [:]
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pointerPoller: Timer?

    var setConcealed: (CGDirectDisplayID, Bool) -> Void = { _, _ in }
    var setFullscreen: (CGDirectDisplayID, Bool) -> Void = { _, _ in }
    var closePopout: (CGDirectDisplayID) -> Void = { _ in }
    var demandChanged: () -> Void = {}

    func rebuild(selected: [ShellScreen], physical: [ShellScreen], dockThickness: CGFloat) {
        let selectedIDs = Set(selected.map { Self.displayID($0.displayID) })
        if let model {
            for id in model.displayOrder where !selectedIDs.contains(id) {
                reduce(.displayRemoved(id))
            }
        }
        cancelAllTimers()

        let physicalDisplays = physical.map {
            BottomDockDisplay(id: Self.displayID($0.displayID), frame: $0.frame)
        }
        let selectedDisplays = selected.map { screen in
            BottomDockDisplay(
                id: Self.displayID(screen.displayID), frame: screen.frame,
                bottomBleed: SidebarBleed.edges(screen: screen.frame, others: physical.map(\.frame), side: .bottom).bottom
            )
        }
        model = BottomDockModel(
            displays: selectedDisplays,
            physicalDisplays: physicalDisplays,
            configuration: BottomDockConfiguration(
                dockThickness: dockThickness,
                bottomBleed: SidebarBleed.depth,
                timing: BottomDockTiming(revealDwell: 0.120, hideGrace: 0.350)
            )
        )
        physicalFrames = Dictionary(uniqueKeysWithValues: physicalDisplays.map { ($0.id, $0.frame) })
        displayIDs = Dictionary(uniqueKeysWithValues: selected.map { (Self.displayID($0.displayID), $0.displayID) })
        for id in displayIDs.values { setConcealed(id, true) }
        syncMonitoring()
        routeCurrentPointer()
        demandChanged()
    }

    func setFullscreenDisplays(_ fullscreen: Set<CGDirectDisplayID>) {
        guard let model else { return }
        for id in model.displayOrder {
            guard let displayID = displayIDs[id] else { continue }
            let suppress = fullscreen.contains(displayID)
            let wasSuppressed = model.state(for: id)?.phase == .fullscreenSuppressed
            guard suppress != wasSuppressed else { continue }
            setFullscreen(displayID, suppress)
            if suppress { closePopout(displayID) }
            reduce(suppress ? .fullscreenEntered(display: id) : .fullscreenExited(display: id))
        }
        routeCurrentPointer()
    }

    func setLease(displayID: CGDirectDisplayID, lease: BottomDockLease, active: Bool) {
        let id = Self.displayID(displayID)
        guard model?.state(for: id) != nil else { return }
        reduce(.interactionLeaseChanged(display: id, lease: lease, isActive: active))
    }

    func tearDown() {
        cancelAllTimers()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        pointerPoller?.invalidate()
        pointerPoller = nil
        model = nil
        physicalFrames = [:]
        displayIDs = [:]
    }

    var hasVisibleDock: Bool {
        guard let model else { return false }
        return model.displayOrder.contains { id in
            switch model.state(for: id)?.phase {
            case .revealed, .hidePending: true
            default: false
            }
        }
    }

    private func syncMonitoring() {
        guard model?.displayOrder.isEmpty == false else {
            tearDown()
            return
        }
        if globalMonitor == nil {
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                MainActor.assumeIsolated { self?.routeCurrentPointer() }
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                MainActor.assumeIsolated { self?.routeCurrentPointer() }
                return event
            }
        }
        if pointerPoller == nil {
            pointerPoller = .repeating(every: 0.05, tolerance: 0.02, owner: self) { $0.routeCurrentPointer() }
        }
    }

    private func routeCurrentPointer() {
        guard model != nil else { return }
        let point = NSEvent.mouseLocation
        let event: BottomDockEvent
        // Utilities' lower-right strip reaches below `screen.minY`; test it
        // before physical ownership so that exterior pixels cannot begin a
        // bottom-dock reveal dwell on their display.
        if shouldYieldUtilitiesTrigger(at: point) {
            event = .pointerLeft
        } else {
            event = .pointerMoved(point)
        }
        reduce(event)
    }

    private func shouldYieldUtilitiesTrigger(at point: CGPoint) -> Bool {
        physicalFrames.values.contains { screen in
            let utilitiesTrigger = EdgeHoverArea.bottomRight(
                screen: screen, width: UtilitiesView.width, height: 0, margin: 25, open: false
            )
            return BottomDockTriggerPolicy.excludesTrigger(point, screen: screen, utilitiesTrigger: utilitiesTrigger)
        }
    }

    private func reduce(_ event: BottomDockEvent) {
        guard let model else { return }
        let reduction = BottomDockReducer.reduce(model, event: event)
        self.model = reduction.model
        for action in reduction.actions { apply(action) }
        demandChanged()
    }

    private func apply(_ action: BottomDockAction) {
        switch action {
        case .scheduleReveal(let id, let token, let delay):
            schedule(id, kind: .reveal, token: token, after: delay)
        case .cancelReveal(let id, _):
            cancel(id, kind: .reveal)
        case .scheduleHide(let id, let token, let delay):
            schedule(id, kind: .hide, token: token, after: delay)
        case .cancelHide(let id, _):
            cancel(id, kind: .hide)
        case .reveal(let id):
            if let displayID = displayIDs[id] { setConcealed(displayID, false) }
        case .conceal(let id):
            if let displayID = displayIDs[id] { setConcealed(displayID, true) }
        }
    }

    private func schedule(_ display: BottomDockDisplayID, kind: TimerKind, token: UInt64, after delay: TimeInterval) {
        cancel(display, kind: kind)
        let key = TimerKey(display: display, kind: kind)
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.timers[key] = nil
            let route: BottomDockTimerRoute = kind == .reveal ? .reveal : .hide
            self.reduce(route.event(display: display, token: token))
        }
        timers[key] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancel(_ display: BottomDockDisplayID, kind: TimerKind) {
        let key = TimerKey(display: display, kind: kind)
        timers.removeValue(forKey: key)?.cancel()
    }

    private func cancelAllTimers() {
        for timer in timers.values { timer.cancel() }
        timers = [:]
    }

    private static func displayID(_ value: CGDirectDisplayID) -> BottomDockDisplayID {
        BottomDockDisplayID(String(value))
    }
}
