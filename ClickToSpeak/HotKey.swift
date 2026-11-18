import AppKit
import Carbon

struct Shortcut {
    let label: String
    let key: UInt32
    let modifiers: UInt32
    static let choices = [
        Shortcut(label: "⌃⇧D", key: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | shiftKey)),
        Shortcut(label: "⌃⇧Espace", key: UInt32(kVK_Space), modifiers: UInt32(controlKey | shiftKey)),
        Shortcut(label: "⌘⇧F8", key: UInt32(kVK_F8), modifiers: UInt32(cmdKey | shiftKey))
    ]
}

@MainActor
final class HotKey {
    private var handler: EventHandlerRef?
    private var registration: EventHotKeyRef?
    private var nextID: UInt32 = 0
    private let signature: OSType = 0x4354536B // CTSk
    private(set) var selected: Int?
    let invoke: () -> Void

    init(invoke: @escaping () -> Void) { self.invoke = invoke }

    func install() -> Bool {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == 0x4354536B else { return OSStatus(eventNotHandledErr) }
            // Carbon application events are dispatched by the AppKit main event loop.
            MainActor.assumeIsolated { Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().invoke() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return false }
        let stored = UserDefaults.standard.integer(forKey: "shortcutIndex")
        return choose(Shortcut.choices.indices.contains(stored) ? stored : 0)
    }

    func choose(_ index: Int) -> Bool {
        guard handler != nil, Shortcut.choices.indices.contains(index) else { return false }
        if index == selected { return true }
        let shortcut = Shortcut.choices[index]
        nextID += 1
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.key, shortcut.modifiers, EventHotKeyID(signature: signature, id: nextID),
                                         GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr else { return false }
        if let registration { UnregisterEventHotKey(registration) }
        registration = replacement
        selected = index
        UserDefaults.standard.set(index, forKey: "shortcutIndex")
        return true
    }

    func uninstall() {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
        registration = nil
        handler = nil
        selected = nil
    }
}
