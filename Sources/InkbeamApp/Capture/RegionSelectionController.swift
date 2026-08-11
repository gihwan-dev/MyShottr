import AppKit
import Foundation

enum RegionSelectionOutcome: Equatable, Sendable {
    case confirmed(RegionSelection)
    case cancelled
}

@MainActor
protocol RegionSelecting: AnyObject {
    func selectRegion() async throws -> RegionSelectionOutcome
    func cancel()
}

enum RegionResizeHandle: CaseIterable, Hashable, Sendable {
    case northWest
    case north
    case northEast
    case east
    case southEast
    case south
    case southWest
    case west

    fileprivate var movesMinimumX: Bool {
        self == .northWest || self == .southWest || self == .west
    }

    fileprivate var movesMaximumX: Bool {
        self == .northEast || self == .southEast || self == .east
    }

    fileprivate var movesMinimumY: Bool {
        self == .southWest || self == .southEast || self == .south
    }

    fileprivate var movesMaximumY: Bool {
        self == .northWest || self == .northEast || self == .north
    }
}

enum RegionSelectionEvent: Sendable {
    case pointerDown(CGPoint)
    case beginMove(CGPoint)
    case beginResize(RegionResizeHandle, CGPoint)
    case pointerDragged(CGPoint)
    case pointerUp
    case confirm
    case cancel
    case setActive(Bool)
}

struct RegionSelectionState: Sendable {
    let display: DisplayDescriptor
    private(set) var selectionRect: CGRect?
    private(set) var isActive: Bool
    private(set) var result: RegionSelectionOutcome?

    private enum Interaction: Sendable {
        case creating(anchor: CGPoint)
        case moving(anchor: CGPoint, original: CGRect)
        case resizing(
            handle: RegionResizeHandle,
            anchor: CGPoint,
            original: CGRect
        )
    }

    private var interaction: Interaction?

    init(
        display: DisplayDescriptor,
        selectionRect: CGRect? = nil,
        isActive: Bool = true
    ) {
        self.display = display
        self.selectionRect = selectionRect
        self.isActive = isActive
    }

    mutating func reduce(_ event: RegionSelectionEvent) {
        switch event {
        case let .pointerDown(point):
            let point = bounded(point)
            isActive = true
            result = nil
            selectionRect = CGRect(origin: point, size: .zero)
            interaction = .creating(anchor: point)

        case let .beginMove(point):
            guard isActive, let selectionRect, !selectionRect.isEmpty else {
                return
            }
            interaction = .moving(
                anchor: point,
                original: selectionRect
            )

        case let .beginResize(handle, point):
            guard isActive, let selectionRect, !selectionRect.isEmpty else {
                return
            }
            interaction = .resizing(
                handle: handle,
                anchor: point,
                original: selectionRect
            )

        case let .pointerDragged(point):
            guard isActive, let interaction else {
                return
            }
            switch interaction {
            case let .creating(anchor):
                selectionRect = normalizedRect(
                    from: anchor,
                    to: bounded(point)
                )

            case let .moving(anchor, original):
                selectionRect = DisplayGeometry.clamp(
                    CGRect(
                        x: original.minX + point.x - anchor.x,
                        y: original.minY + point.y - anchor.y,
                        width: original.width,
                        height: original.height
                    ),
                    to: display
                )

            case let .resizing(handle, anchor, original):
                selectionRect = resizedRect(
                    original,
                    handle: handle,
                    delta: CGVector(
                        dx: point.x - anchor.x,
                        dy: point.y - anchor.y
                    )
                )
            }

        case .pointerUp:
            guard isActive else {
                return
            }
            let completedCreation: Bool
            if case .creating = interaction {
                completedCreation = true
            } else {
                completedCreation = false
            }
            interaction = nil
            guard
                completedCreation,
                let selectionRect,
                !selectionRect.isEmpty
            else {
                return
            }
            result = .confirmed(
                RegionSelection(
                    display: display,
                    rectInDisplayPoints: selectionRect
                )
            )

        case .confirm:
            guard
                isActive,
                let selectionRect,
                !selectionRect.isEmpty
            else {
                return
            }
            result = .confirmed(
                RegionSelection(
                    display: display,
                    rectInDisplayPoints: selectionRect
                )
            )

        case .cancel:
            result = .cancelled
            interaction = nil

        case let .setActive(active):
            isActive = active
            if !active {
                interaction = nil
            }
        }
    }

    private func bounded(_ point: CGPoint) -> CGPoint {
        let size = display.frameInAppKitPoints.size
        return CGPoint(
            x: min(max(0, point.x), size.width),
            y: min(max(0, point.y), size.height)
        )
    }

    private func normalizedRect(from first: CGPoint, to second: CGPoint) -> CGRect {
        CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }

    private func resizedRect(
        _ original: CGRect,
        handle: RegionResizeHandle,
        delta: CGVector
    ) -> CGRect {
        let bounds = CGRect(
            origin: .zero,
            size: display.frameInAppKitPoints.size
        )
        var minimumX = original.minX
        var maximumX = original.maxX
        var minimumY = original.minY
        var maximumY = original.maxY

        if handle.movesMinimumX {
            minimumX = min(max(bounds.minX, minimumX + delta.dx), bounds.maxX)
        }
        if handle.movesMaximumX {
            maximumX = min(max(bounds.minX, maximumX + delta.dx), bounds.maxX)
        }
        if handle.movesMinimumY {
            minimumY = min(max(bounds.minY, minimumY + delta.dy), bounds.maxY)
        }
        if handle.movesMaximumY {
            maximumY = min(max(bounds.minY, maximumY + delta.dy), bounds.maxY)
        }

        return CGRect(
            x: min(minimumX, maximumX),
            y: min(minimumY, maximumY),
            width: abs(maximumX - minimumX),
            height: abs(maximumY - minimumY)
        )
    }
}

@MainActor
final class RegionSelectionController: RegionSelecting {
    typealias DisplayProvider = @MainActor () -> [DisplayDescriptor]
    typealias PanelFactory = @MainActor (
        _ display: DisplayDescriptor,
        _ view: RegionSelectionView
    ) -> RegionSelectionPanel
    typealias CursorAction = @MainActor () -> Void

    private let displays: DisplayProvider
    private let panelFactory: PanelFactory
    private let activateCrosshair: CursorAction
    private let restoreCursor: CursorAction

    private var continuation: CheckedContinuation<
        RegionSelectionOutcome,
        any Error
    >?
    private var panels: [UInt32: RegionSelectionPanel] = [:]
    private var views: [UInt32: RegionSelectionView] = [:]
    private var states: [UInt32: RegionSelectionState] = [:]
    private var activeDisplayID: UInt32?
    private var keyEventMonitor: Any?
    private var isCursorOverrideActive = false

    var isSelecting: Bool {
        continuation != nil
    }

    init(
        displays: @escaping DisplayProvider = RegionSelectionController.currentDisplays,
        panelFactory: @escaping PanelFactory = {
            RegionSelectionPanel(display: $0, contentView: $1)
        },
        activateCrosshair: @escaping CursorAction = {
            NSCursor.crosshair.push()
        },
        restoreCursor: @escaping CursorAction = {
            NSCursor.pop()
        }
    ) {
        self.displays = displays
        self.panelFactory = panelFactory
        self.activateCrosshair = activateCrosshair
        self.restoreCursor = restoreCursor
    }

    func selectRegion() async throws -> RegionSelectionOutcome {
        guard continuation == nil else {
            throw CaptureError.captureAlreadyInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            presentPanels()
        }
    }

    func cancel() {
        finish(with: .cancelled)
    }

    func handle(_ event: RegionSelectionEvent, from displayID: UInt32) {
        guard continuation != nil, states[displayID] != nil else {
            return
        }

        switch event {
        case .cancel:
            finish(with: .cancelled)
            return

        case .pointerDown:
            activate(displayID)

        case .setActive:
            return

        default:
            guard activeDisplayID == displayID else {
                return
            }
        }

        guard var state = states[displayID] else {
            return
        }
        state.reduce(event)
        states[displayID] = state
        updateView(for: displayID)

        if let result = state.result {
            finish(with: result)
        }
    }

    private func presentPanels() {
        let currentDisplays = displays()
        guard !currentDisplays.isEmpty else {
            finish(with: .cancelled)
            return
        }

        for display in currentDisplays {
            let view = RegionSelectionView(display: display)
            view.onAction = { [weak self] event in
                self?.handle(event, from: display.displayID)
            }

            let panel = panelFactory(display, view)
            panel.onCancel = { [weak self] in
                self?.cancel()
            }
            panel.onConfirm = { [weak self] in
                guard let self, let activeDisplayID = self.activeDisplayID else {
                    return
                }
                self.handle(.confirm, from: activeDisplayID)
            }

            states[display.displayID] = RegionSelectionState(
                display: display,
                isActive: false
            )
            views[display.displayID] = view
            panels[display.displayID] = panel
            panel.beginCapture()
        }

        activateCrosshair()
        isCursorOverrideActive = true

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self, self.isSelecting else {
                return event
            }
            switch event.keyCode {
            case 53:
                self.cancel()
                return nil
            case 36, 76:
                guard let activeDisplayID = self.activeDisplayID else {
                    return nil
                }
                self.handle(.confirm, from: activeDisplayID)
                return nil
            default:
                return event
            }
        }
    }

    private func activate(_ displayID: UInt32) {
        activeDisplayID = displayID

        for (candidateID, state) in states {
            if candidateID == displayID {
                var activeState = state
                activeState.reduce(.setActive(true))
                states[candidateID] = activeState
            } else {
                states[candidateID] = RegionSelectionState(
                    display: state.display,
                    isActive: false
                )
                updateView(for: candidateID)
            }
        }

        panels[displayID]?.activateForCapture()
    }

    private func updateView(for displayID: UInt32) {
        views[displayID]?.selectionRect = states[displayID]?.selectionRect
    }

    private func finish(with result: RegionSelectionOutcome) {
        guard let continuation else {
            return
        }
        self.continuation = nil

        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }

        let visiblePanels = Array(panels.values)
        for panel in visiblePanels {
            panel.onCancel = nil
            panel.onConfirm = nil
            panel.orderOut(nil)
        }

        if isCursorOverrideActive {
            restoreCursor()
            isCursorOverrideActive = false
        }

        activeDisplayID = nil
        panels.removeAll()
        views.removeAll()
        states.removeAll()
        continuation.resume(returning: result)
    }

    private static func currentDisplays() -> [DisplayDescriptor] {
        NSScreen.screens.compactMap { screen in
            guard
                let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber
            else {
                return nil
            }

            let scale = screen.backingScaleFactor
            return DisplayDescriptor(
                displayID: number.uint32Value,
                frameInAppKitPoints: screen.frame,
                scale: scale,
                pixelSize: CGSize(
                    width: screen.frame.width * scale,
                    height: screen.frame.height * scale
                )
            )
        }
    }
}
