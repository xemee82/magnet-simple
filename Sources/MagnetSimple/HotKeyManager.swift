import Carbon
import AppKit

enum HotKeyAction: UInt32 {
    case leftHalf  = 1
    case rightHalf = 2
    case maximize  = 3
}

class HotKeyManager {
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    var onAction: ((HotKeyAction) -> Void)?

    func registerAll() {
        unregisterAll()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        guard status == noErr else {
            NSLog("[HotKeyManager] Failed to install Carbon event handler: %d", status)
            return
        }

        // 默认标准快捷键：Control + Option + 方向键/回车
        let dualModifiers = UInt32(controlKey | optionKey)
        register(keyCode: UInt32(kVK_LeftArrow),  modifiers: dualModifiers, id: .leftHalf)
        register(keyCode: UInt32(kVK_RightArrow), modifiers: dualModifiers, id: .rightHalf)
        register(keyCode: UInt32(kVK_Return),     modifiers: dualModifiers, id: .maximize)

        // 静默兼容模式：仅按 Control + 方向键/回车（无缝适配仅有 Control 键的键盘）
        let singleModifier = UInt32(controlKey)
        register(keyCode: UInt32(kVK_LeftArrow),  modifiers: singleModifier, id: .leftHalf)
        register(keyCode: UInt32(kVK_RightArrow), modifiers: singleModifier, id: .rightHalf)
        register(keyCode: UInt32(kVK_Return),     modifiers: singleModifier, id: .maximize)
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: HotKeyAction) {
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x4D53_4D50),  // "MSMP"
            id: id.rawValue
        )
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs.append(ref)
        } else {
            NSLog("[HotKeyManager] Failed to register hotkey %d, status: %d", id.rawValue, status)
        }
    }

    func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        if let handlerRef = eventHandlerRef {
            RemoveEventHandler(handlerRef)
            eventHandlerRef = nil
        }
    }

    deinit {
        unregisterAll()
    }
}

private func hotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event, let userData = userData else {
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

    guard status == noErr else {
        return status
    }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    if let action = HotKeyAction(rawValue: hotKeyID.id) {
        DispatchQueue.main.async {
            manager.onAction?(action)
        }
        return noErr
    }

    return OSStatus(eventNotHandledErr)
}
