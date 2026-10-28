import Carbon.HIToolbox
import ScenesCore

final class HotkeyCenter {
    private var refs: [EventHotKeyRef] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var installed = false

    static func keyCode(forDigit digit: Character) -> UInt32? {
        let table: [Character: Int] = [
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9
        ]
        return table[digit].map { UInt32($0) }
    }

    static func carbonModifiers(_ spec: HotkeySpec) -> UInt32 {
        var m = 0
        if spec.control { m |= controlKey }
        if spec.option { m |= optionKey }
        if spec.command { m |= cmdKey }
        if spec.shift { m |= shiftKey }
        return UInt32(m)
    }

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x444E_5A53), id: id)  // 'DNZS'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
            handlers[id] = action
        } else {
            NSLog("DNZ-Scenes: could not register hotkey id %u (status %d)", id, status)
        }
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            center.handlers[hotKeyID.id]?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        installed = true
    }
}
