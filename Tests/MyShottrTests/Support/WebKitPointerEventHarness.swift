import AppKit
import ObjectiveC.runtime
import WebKit

@MainActor
struct WebKitPointerEventHarness {
    private enum MouseAction {
        case down
        case dragged
        case up

        var eventType: NSEvent.EventType {
            switch self {
            case .down:
                return .leftMouseDown
            case .dragged:
                return .leftMouseDragged
            case .up:
                return .leftMouseUp
            }
        }

        var pressedMouseButtons: Int {
            switch self {
            case .down, .dragged:
                return 1 << 0
            case .up:
                return 0
            }
        }

        var pressure: Float {
            switch self {
            case .down:
                return 1
            case .dragged, .up:
                return 0
            }
        }
    }

    private enum HarnessError: LocalizedError {
        case missingPrivateSelector(String)
        case missingRuntimeMethod(String)
        case missingTarget(NSPoint)
        case unexpectedTarget(String)
        case eventCreationFailed(NSEvent.EventType)
        case missingDragOrigin
        case missingCGEvent
        case rebuiltEventCreationFailed
        case buttonStateMismatch(expected: Int, actual: Int)
        case buttonNumberMismatch(expected: Int, actual: Int)

        var errorDescription: String? {
            switch self {
            case let .missingPrivateSelector(selector):
                return "Required WebKit test selector is unavailable: \(selector)"
            case let .missingRuntimeMethod(selector):
                return "Required Objective-C runtime method is unavailable: \(selector)"
            case let .missingTarget(point):
                return "No AppKit event target exists at window point \(point)"
            case let .unexpectedTarget(target):
                return "Expected the WKWebView as the direct event target, got \(target)"
            case let .eventCreationFailed(type):
                return "Could not create AppKit mouse event of type \(type.rawValue)"
            case .missingDragOrigin:
                return "A left-mouse drag requires the previous window point"
            case .missingCGEvent:
                return "The left-mouse drag NSEvent has no backing CGEvent"
            case .rebuiltEventCreationFailed:
                return "Could not rebuild the left-mouse drag from its CGEvent"
            case let .buttonStateMismatch(expected, actual):
                return "NSEvent.pressedMouseButtons was \(actual), expected \(expected)"
            case let .buttonNumberMismatch(expected, actual):
                return "NSEvent.buttonNumber was \(actual), expected \(expected)"
            }
        }
    }

    private typealias SetCurrentEventImplementation = @convention(c) (
        AnyObject,
        Selector,
        NSEvent?
    ) -> Void

    private typealias PendingMouseEventsImplementation = @convention(c) (
        AnyObject,
        Selector,
        @convention(block) () -> Void
    ) -> Void

    private typealias SimulateMouseMoveImplementation = @convention(c) (
        AnyObject,
        Selector,
        NSEvent
    ) -> Void

    private static let setCurrentEventSelector = NSSelectorFromString(
        "_setCurrentEvent:"
    )
    private static let pendingMouseEventsSelector = NSSelectorFromString(
        "_doAfterProcessingAllPendingMouseEvents:"
    )
    private static let simulateMouseMoveSelector = NSSelectorFromString(
        "_simulateMouseMove:"
    )
    private static let pressedMouseButtonsSelector = #selector(
        getter: NSEvent.pressedMouseButtons
    )
    private static let buttonNumberSelector = #selector(
        getter: NSEvent.buttonNumber
    )

    private let webView: WKWebView
    private let window: NSWindow
    private let application: NSApplication
    private let pressedMouseButtonsMethod: Method
    private let buttonNumberMethod: Method
    private let setCurrentEvent: SetCurrentEventImplementation
    private let doAfterProcessingAllPendingMouseEvents:
        PendingMouseEventsImplementation
    private let simulateMouseMove: SimulateMouseMoveImplementation

    init(webView: WKWebView, window: NSWindow) throws {
        let application = NSApplication.shared
        guard application.responds(to: Self.setCurrentEventSelector) else {
            throw HarnessError.missingPrivateSelector(
                NSStringFromSelector(Self.setCurrentEventSelector)
            )
        }
        guard webView.responds(to: Self.pendingMouseEventsSelector) else {
            throw HarnessError.missingPrivateSelector(
                NSStringFromSelector(Self.pendingMouseEventsSelector)
            )
        }
        guard webView.responds(to: Self.simulateMouseMoveSelector) else {
            throw HarnessError.missingPrivateSelector(
                NSStringFromSelector(Self.simulateMouseMoveSelector)
            )
        }
        guard let pressedMouseButtonsMethod = class_getClassMethod(
            NSEvent.self,
            Self.pressedMouseButtonsSelector
        ) else {
            throw HarnessError.missingRuntimeMethod(
                NSStringFromSelector(Self.pressedMouseButtonsSelector)
            )
        }
        guard let buttonNumberMethod = class_getInstanceMethod(
            NSEvent.self,
            Self.buttonNumberSelector
        ) else {
            throw HarnessError.missingRuntimeMethod(
                NSStringFromSelector(Self.buttonNumberSelector)
            )
        }

        self.webView = webView
        self.window = window
        self.application = application
        self.pressedMouseButtonsMethod = pressedMouseButtonsMethod
        self.buttonNumberMethod = buttonNumberMethod
        setCurrentEvent = unsafeBitCast(
            application.method(for: Self.setCurrentEventSelector),
            to: SetCurrentEventImplementation.self
        )
        doAfterProcessingAllPendingMouseEvents = unsafeBitCast(
            webView.method(for: Self.pendingMouseEventsSelector),
            to: PendingMouseEventsImplementation.self
        )
        simulateMouseMove = unsafeBitCast(
            webView.method(for: Self.simulateMouseMoveSelector),
            to: SimulateMouseMoveImplementation.self
        )
    }

    func dragLeftButton(from start: NSPoint, to end: NSPoint) async throws {
        let target = try resolvedTarget(at: start)
        let timestamp = ProcessInfo.processInfo.systemUptime

        try await synchronizePointer(
            at: start,
            timestamp: timestamp,
            eventNumber: 1
        )
        try await dispatch(
            .down,
            at: start,
            previousLocation: nil,
            timestamp: timestamp + 0.001,
            eventNumber: 2,
            to: target
        )
        try await dispatch(
            .dragged,
            at: end,
            previousLocation: start,
            timestamp: timestamp + 0.002,
            eventNumber: 3,
            to: target
        )
        try await dispatch(
            .up,
            at: end,
            previousLocation: nil,
            timestamp: timestamp + 0.003,
            eventNumber: 4,
            to: target
        )
    }

    func clickLeftButton(at location: NSPoint) async throws {
        let target = try resolvedTarget(at: location)
        let timestamp = ProcessInfo.processInfo.systemUptime

        try await synchronizePointer(
            at: location,
            timestamp: timestamp,
            eventNumber: 1
        )
        try await dispatch(
            .down,
            at: location,
            previousLocation: nil,
            timestamp: timestamp + 0.001,
            eventNumber: 2,
            to: target
        )
        try await dispatch(
            .up,
            at: location,
            previousLocation: nil,
            timestamp: timestamp + 0.002,
            eventNumber: 3,
            to: target
        )
    }

    private func synchronizePointer(
        at location: NSPoint,
        timestamp: TimeInterval,
        eventNumber: Int
    ) async throws {
        guard let event = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: location,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: NSGraphicsContext.current,
            eventNumber: eventNumber,
            clickCount: 0,
            pressure: 0
        ) else {
            throw HarnessError.eventCreationFailed(.mouseMoved)
        }

        // WebKitTestRunner synchronizes WebKit's pointer position before the
        // down/drag/up sequence so the drag CGEvent delta is applied from the
        // deterministic starting point.
        // https://github.com/WebKit/WebKit/blob/main/Tools/WebKitTestRunner/mac/EventSenderProxy.mm
        try withScopedButtonState(
            pressedMouseButtons: 0,
            buttonNumber: 0
        ) {
            try withCurrentApplicationEvent(event) {
                guard NSEvent.pressedMouseButtons == 0 else {
                    throw HarnessError.buttonStateMismatch(
                        expected: 0,
                        actual: NSEvent.pressedMouseButtons
                    )
                }
                guard event.buttonNumber == 0 else {
                    throw HarnessError.buttonNumberMismatch(
                        expected: 0,
                        actual: event.buttonNumber
                    )
                }
                simulateMouseMove(
                    webView,
                    Self.simulateMouseMoveSelector,
                    event
                )
            }
        }

        await drainPendingMouseEvents()
    }

    private func resolvedTarget(at point: NSPoint) throws -> NSView {
        guard let target = window.contentView?.hitTest(point) else {
            throw HarnessError.missingTarget(point)
        }
        guard target === webView else {
            throw HarnessError.unexpectedTarget(String(describing: target))
        }
        return target
    }

    private func dispatch(
        _ action: MouseAction,
        at location: NSPoint,
        previousLocation: NSPoint?,
        timestamp: TimeInterval,
        eventNumber: Int,
        to target: NSView
    ) async throws {
        let event = try mouseEvent(
            for: action,
            at: location,
            previousLocation: previousLocation,
            timestamp: timestamp,
            eventNumber: eventNumber
        )

        // This is the minimum test-bundle-only cluster used by WebKit's macOS
        // EventSenderProxy: scoped NSEvent button-state overrides, a current
        // application event, and direct target delivery.
        // https://github.com/WebKit/WebKit/blob/main/Tools/WebKitTestRunner/mac/EventSenderProxy.mm
        try withScopedButtonState(
            pressedMouseButtons: action.pressedMouseButtons,
            buttonNumber: 0
        ) {
            try withCurrentApplicationEvent(event) {
                guard NSEvent.pressedMouseButtons == action.pressedMouseButtons else {
                    throw HarnessError.buttonStateMismatch(
                        expected: action.pressedMouseButtons,
                        actual: NSEvent.pressedMouseButtons
                    )
                }
                guard event.buttonNumber == 0 else {
                    throw HarnessError.buttonNumberMismatch(
                        expected: 0,
                        actual: event.buttonNumber
                    )
                }

                switch action {
                case .down:
                    target.mouseDown(with: event)
                case .dragged:
                    target.mouseDragged(with: event)
                case .up:
                    target.mouseUp(with: event)
                }
            }
        }

        // WebKit exposes this testing drain in WKWebViewPrivateForTesting so
        // completion observes the mouse IPC that direct AppKit delivery queued.
        // https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivateForTesting.h
        await drainPendingMouseEvents()
    }

    private func drainPendingMouseEvents() async {
        await withCheckedContinuation { continuation in
            let completion: @convention(block) () -> Void = {
                continuation.resume()
            }
            doAfterProcessingAllPendingMouseEvents(
                webView,
                Self.pendingMouseEventsSelector,
                completion
            )
        }
    }

    private func mouseEvent(
        for action: MouseAction,
        at location: NSPoint,
        previousLocation: NSPoint?,
        timestamp: TimeInterval,
        eventNumber: Int
    ) throws -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: action.eventType,
            location: location,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: NSGraphicsContext.current,
            eventNumber: eventNumber,
            clickCount: 1,
            pressure: action.pressure
        ) else {
            throw HarnessError.eventCreationFailed(action.eventType)
        }
        guard case .dragged = action else {
            return event
        }
        guard let previousLocation else {
            throw HarnessError.missingDragOrigin
        }
        guard let cgEvent = event.cgEvent else {
            throw HarnessError.missingCGEvent
        }
        cgEvent.setIntegerValueField(
            .mouseEventDeltaX,
            value: Int64(location.x - previousLocation.x)
        )
        cgEvent.setIntegerValueField(
            .mouseEventDeltaY,
            value: Int64(-(location.y - previousLocation.y))
        )
        guard let rebuiltEvent = NSEvent(cgEvent: cgEvent) else {
            throw HarnessError.rebuiltEventCreationFailed
        }
        return rebuiltEvent
    }

    private func withCurrentApplicationEvent<T>(
        _ event: NSEvent,
        action: () throws -> T
    ) rethrows -> T {
        let previousEvent = application.currentEvent
        setCurrentEvent(
            application,
            Self.setCurrentEventSelector,
            event
        )
        defer {
            setCurrentEvent(
                application,
                Self.setCurrentEventSelector,
                previousEvent
            )
        }
        return try action()
    }

    private func withScopedButtonState<T>(
        pressedMouseButtons: Int,
        buttonNumber: Int,
        action: () throws -> T
    ) rethrows -> T {
        let pressedMouseButtonsBlock: @convention(block) (AnyObject) -> Int = {
            _ in pressedMouseButtons
        }
        let buttonNumberBlock: @convention(block) (AnyObject) -> Int = {
            _ in buttonNumber
        }
        let replacementPressedMouseButtons = imp_implementationWithBlock(
            pressedMouseButtonsBlock
        )
        let replacementButtonNumber = imp_implementationWithBlock(
            buttonNumberBlock
        )
        let originalPressedMouseButtons = method_setImplementation(
            pressedMouseButtonsMethod,
            replacementPressedMouseButtons
        )
        let originalButtonNumber = method_setImplementation(
            buttonNumberMethod,
            replacementButtonNumber
        )
        defer {
            method_setImplementation(
                buttonNumberMethod,
                originalButtonNumber
            )
            method_setImplementation(
                pressedMouseButtonsMethod,
                originalPressedMouseButtons
            )
            precondition(imp_removeBlock(replacementButtonNumber))
            precondition(imp_removeBlock(replacementPressedMouseButtons))
        }

        return try action()
    }
}
