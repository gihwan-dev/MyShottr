import AppKit
import Carbon
import XCTest
@testable import MyShottr

@MainActor
final class GlobalHotKeyRegistrarTests: XCTestCase {
    func testRegistersCommandShift2AndInvokesActionForHotKeyEvent() async throws {
        let harness = GlobalHotKeyAPIHarness()
        var actionCount = 0
        let registrar = try GlobalHotKeyRegistrar(
            api: harness.api,
            action: {
                actionCount += 1
            }
        )

        XCTAssertEqual(harness.keyCode, UInt32(kVK_ANSI_2))
        XCTAssertEqual(
            harness.modifiers,
            UInt32(cmdKey | shiftKey)
        )
        XCTAssertEqual(
            harness.options,
            UInt32(kEventHotKeyExclusive)
        )
        XCTAssertNotNil(harness.eventHandler)
        XCTAssertNotNil(harness.eventHandlerContext)

        harness.invokeEventHandler(
            signature: 0x4D_53_48_54,
            id: 1
        )
        await Task.yield()

        XCTAssertEqual(actionCount, 1)
        withExtendedLifetime(registrar) {}
    }

    func testIgnoresHotKeyEventWithDifferentIdentifier() throws {
        let harness = GlobalHotKeyAPIHarness()
        var actionCount = 0
        let registrar = try GlobalHotKeyRegistrar(
            api: harness.api,
            action: {
                actionCount += 1
            }
        )

        harness.invokeEventHandler(
            signature: 0x4D_53_48_54,
            id: 99
        )

        XCTAssertEqual(actionCount, 0)
        withExtendedLifetime(registrar) {}
    }

    func testRegistrationConflictThrowsStatusAndRemovesInstalledHandler() {
        let harness = GlobalHotKeyAPIHarness(
            registrationStatus: OSStatus(eventHotKeyExistsErr)
        )

        XCTAssertThrowsError(
            try GlobalHotKeyRegistrar(api: harness.api, action: {})
        ) { error in
            XCTAssertEqual(
                error as? GlobalHotKeyError,
                .registrationFailed(OSStatus(eventHotKeyExistsErr))
            )
        }
        XCTAssertEqual(harness.removedHandlers.count, 1)
        XCTAssertTrue(harness.unregisteredHotKeys.isEmpty)
    }

    func testDeinitializationUnregistersHotKeyAndRemovesEventHandler() throws {
        let harness = GlobalHotKeyAPIHarness()
        do {
            let registrar = try GlobalHotKeyRegistrar(
                api: harness.api,
                action: {}
            )
            withExtendedLifetime(registrar) {}
        }

        XCTAssertEqual(harness.unregisteredHotKeys.count, 1)
        XCTAssertEqual(harness.removedHandlers.count, 1)
    }
}

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testCreatesRequiredTemplateIconAndExactMenuCommands() throws {
        let image = NSImage(
            size: NSSize(width: 18, height: 18),
            flipped: false
        ) { _ in true }
        let controller = try MenuBarController(
            captureArea: {},
            openProject: {},
            quit: {},
            imageLoader: { name in
                XCTAssertEqual(name, NSImage.Name("StatusBarIcon"))
                return image
            }
        )

        XCTAssertTrue(image.isTemplate)
        XCTAssertTrue(controller.statusItem.button?.image === image)

        let menu = try XCTUnwrap(controller.statusItem.menu)
        XCTAssertEqual(menu.items.map(\.title), [
            "Capture Area",
            "Open Project…",
            "",
            "Quit MyShottr",
        ])
        XCTAssertEqual(menu.items[0].keyEquivalent, "2")
        XCTAssertEqual(
            menu.items[0].keyEquivalentModifierMask,
            [.command, .shift]
        )
        XCTAssertTrue(menu.items[2].isSeparatorItem)
        XCTAssertTrue(menu.items[1].keyEquivalent.isEmpty)
        XCTAssertTrue(menu.items[3].keyEquivalent.isEmpty)
    }

    func testMissingStatusIconIsExplicitInitializationError() {
        XCTAssertThrowsError(
            try MenuBarController(
                captureArea: {},
                openProject: {},
                quit: {},
                imageLoader: { _ in nil }
            )
        ) { error in
            XCTAssertEqual(
                error as? MenuBarControllerError,
                .missingStatusIcon
            )
        }
    }
}

private final class GlobalHotKeyAPIHarness {
    private let registrationStatus: OSStatus
    private(set) var keyCode: UInt32?
    private(set) var modifiers: UInt32?
    private(set) var options: UInt32?
    private(set) var eventHandler: EventHandlerUPP?
    private(set) var eventHandlerContext: UnsafeMutableRawPointer?
    private(set) var unregisteredHotKeys: [EventHotKeyRef] = []
    private(set) var removedHandlers: [EventHandlerRef] = []

    private let hotKey = OpaquePointer(bitPattern: 0x101)!
    private let handler = OpaquePointer(bitPattern: 0x202)!

    init(registrationStatus: OSStatus = noErr) {
        self.registrationStatus = registrationStatus
    }

    lazy var api = GlobalHotKeyAPI(
        installEventHandler: {
            [weak self] eventHandler, context, outputHandler in
            guard let self else {
                return OSStatus(eventInternalErr)
            }
            self.eventHandler = eventHandler
            self.eventHandlerContext = context
            outputHandler.pointee = self.handler
            return noErr
        },
        registerEventHotKey: {
            [weak self] keyCode, modifiers, options, outputHotKey in
            guard let self else {
                return OSStatus(eventInternalErr)
            }
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.options = options
            if self.registrationStatus == noErr {
                outputHotKey.pointee = self.hotKey
            }
            return self.registrationStatus
        },
        unregisterEventHotKey: { [weak self] hotKey in
            if let hotKey {
                self?.unregisteredHotKeys.append(hotKey)
            }
            return noErr
        },
        removeEventHandler: { [weak self] handler in
            if let handler {
                self?.removedHandlers.append(handler)
            }
            return noErr
        }
    )

    func invokeEventHandler(signature: OSType, id: UInt32) {
        var event: EventRef?
        let creationStatus = CreateEvent(
            nil,
            OSType(kEventClassKeyboard),
            UInt32(kEventHotKeyPressed),
            GetCurrentEventTime(),
            EventAttributes(kEventAttributeUserEvent),
            &event
        )
        precondition(creationStatus == noErr)
        guard let event else {
            preconditionFailure("Carbon did not create a hot-key event")
        }
        defer {
            ReleaseEvent(event)
        }

        var hotKeyID = EventHotKeyID(
            signature: signature,
            id: id
        )
        let parameterStatus = SetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            MemoryLayout<EventHotKeyID>.size,
            &hotKeyID
        )
        precondition(parameterStatus == noErr)
        _ = eventHandler?(nil, event, eventHandlerContext)
    }
}
