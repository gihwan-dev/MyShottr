import Carbon
import Foundation

private let inkbeamHotKeySignature: OSType = 0x49_4E_4B_42
private let inkbeamHotKeyID: UInt32 = 1

enum GlobalHotKeyError: Error, Equatable {
    case registrationFailed(OSStatus)
}

struct GlobalHotKeyAPI {
    typealias InstallEventHandler = (
        _ handler: EventHandlerUPP,
        _ context: UnsafeMutableRawPointer,
        _ outputHandler: UnsafeMutablePointer<EventHandlerRef?>
    ) -> OSStatus
    typealias RegisterEventHotKey = (
        _ keyCode: UInt32,
        _ modifiers: UInt32,
        _ options: UInt32,
        _ outputHotKey: UnsafeMutablePointer<EventHotKeyRef?>
    ) -> OSStatus

    let installEventHandler: InstallEventHandler
    let registerEventHotKey: RegisterEventHotKey
    let unregisterEventHotKey: (EventHotKeyRef?) -> OSStatus
    let removeEventHandler: (EventHandlerRef?) -> OSStatus

    @MainActor
    static let live = GlobalHotKeyAPI(
        installEventHandler: { handler, context, outputHandler in
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            return Carbon.InstallEventHandler(
                GetApplicationEventTarget(),
                handler,
                1,
                &eventType,
                context,
                outputHandler
            )
        },
        registerEventHotKey: {
            keyCode,
            modifiers,
            options,
            outputHotKey in
            Carbon.RegisterEventHotKey(
                keyCode,
                modifiers,
                EventHotKeyID(
                    signature: inkbeamHotKeySignature,
                    id: inkbeamHotKeyID
                ),
                GetApplicationEventTarget(),
                options,
                outputHotKey
            )
        },
        unregisterEventHotKey: Carbon.UnregisterEventHotKey,
        removeEventHandler: Carbon.RemoveEventHandler
    )
}

final class GlobalHotKeyRegistrar: @unchecked Sendable {
    private let api: GlobalHotKeyAPI
    private let action: @MainActor () -> Void
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    @MainActor
    init(
        api: GlobalHotKeyAPI = .live,
        action: @escaping @MainActor () -> Void
    ) throws {
        self.api = api
        self.action = action

        var eventHandler: EventHandlerRef?
        let handlerStatus = api.installEventHandler(
            globalHotKeyEventHandler,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            throw GlobalHotKeyError.registrationFailed(handlerStatus)
        }
        self.eventHandler = eventHandler

        var hotKey: EventHotKeyRef?
        let registrationStatus = api.registerEventHotKey(
            UInt32(kVK_ANSI_2),
            UInt32(cmdKey | shiftKey),
            UInt32(kEventHotKeyExclusive),
            &hotKey
        )
        guard registrationStatus == noErr else {
            _ = api.removeEventHandler(eventHandler)
            self.eventHandler = nil
            throw GlobalHotKeyError.registrationFailed(
                registrationStatus
            )
        }
        self.hotKey = hotKey
    }

    deinit {
        if let hotKey {
            _ = api.unregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            _ = api.removeEventHandler(eventHandler)
        }
    }

    @MainActor
    fileprivate func invokeAction() {
        action()
    }
}

private func globalHotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let context else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr,
          hotKeyID.signature == inkbeamHotKeySignature,
          hotKeyID.id == inkbeamHotKeyID
    else {
        return OSStatus(eventNotHandledErr)
    }

    let registrar = Unmanaged<GlobalHotKeyRegistrar>
        .fromOpaque(context)
        .takeUnretainedValue()
    MainActor.assumeIsolated {
        registrar.invokeAction()
    }
    return noErr
}
