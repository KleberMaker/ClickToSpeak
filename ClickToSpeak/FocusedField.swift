import AppKit
import ApplicationServices
import Carbon

private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
    return result
}

private func elementAttribute(_ element: AXUIElement, _ key: String) -> AXUIElement? {
    guard let result = attribute(element, key), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
    return (result as! AXUIElement)
}

private func canSet(_ element: AXUIElement, _ key: String) -> Bool {
    var settable = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(element, key as CFString, &settable) == .success && settable.boolValue
}

private func selectedRange(_ element: AXUIElement) -> NSRange? {
    guard let value = attribute(element, kAXSelectedTextRangeAttribute),
          CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var range = CFRange()
    guard AXValueGetValue(value as! AXValue, .cfRange, &range),
          range.location >= 0, range.length >= 0, range.length <= Int.max - range.location else { return nil }
    return NSRange(location: range.location, length: range.length)
}

private func rangeValue(_ range: NSRange) -> AXValue? {
    var value = CFRange(location: range.location, length: range.length)
    return AXValueCreate(.cfRange, &value)
}

@MainActor
final class FocusedField {
    private let element: AXUIElement
    let pid: pid_t
    private var document: DictatedText
    private var focusObserver: AXObserver?
    private var focusLost: (() -> Void)?
    private static let unavailable = DictationError.message("Insertion indisponible. Placez le curseur dans un champ de texte modifiable.")
    private static let changed = DictationError.message("Dictée arrêtée. Le champ ou son contenu a changé.")

    private init(element: AXUIElement, pid: pid_t, document: DictatedText) {
        self.element = element
        self.pid = pid
        self.document = document
    }

    private static func focused(_ pid: pid_t) -> AXUIElement? {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
        return elementAttribute(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute)
    }

    private static func isProtected(_ el: AXUIElement) -> Bool {
        if IsSecureEventInputEnabled() { return true }
        var candidate: AXUIElement? = el
        for _ in 0..<8 {
            guard let item = candidate else { break }
            if attribute(item, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole ||
                (attribute(item, "AXProtectedContent") as? Bool) == true { return true }
            candidate = elementAttribute(item, kAXParentAttribute)
        }
        return false
    }

    static func capture(pid: pid_t) throws -> FocusedField {
        guard pid != ProcessInfo.processInfo.processIdentifier, let el = focused(pid) else { throw unavailable }
        guard !isProtected(el) else { throw DictationError.message("La dictée est désactivée dans les champs protégés.") }
        guard (attribute(el, kAXEnabledAttribute) as? Bool) != false,
              (attribute(el, "AXEditable") as? Bool) != false,
              canSet(el, kAXSelectedTextRangeAttribute), canSet(el, kAXSelectedTextAttribute),
              let selection = selectedRange(el), let value = attribute(el, kAXValueAttribute) as? String else { throw unavailable }
        return try FocusedField(element: el, pid: pid, document: DictatedText(original: value, selection: selection))
    }

    private func ensureFocus() throws {
        guard let current = Self.focused(pid), CFEqual(current, element), !Self.isProtected(current) else { throw Self.changed }
    }

    private func verify(_ expected: String, selection: NSRange) throws {
        try ensureFocus()
        guard selectedRange(element) == selection,
              let value = attribute(element, kAXValueAttribute) as? String,
              value.utf16.elementsEqual(expected.utf16) else { throw Self.changed }
    }

    func validate() throws { try verify(document.expected, selection: document.selection) }

    // Some web editors omit focus notifications. The periodic check covers those hosts.
    func watchFocus(_ lost: @escaping () -> Void) {
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, focusedElement, _, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                let field = Unmanaged<FocusedField>.fromOpaque(context).takeUnretainedValue()
                if !CFEqual(field.element, focusedElement) { field.focusLost?() }
            }
        }, &observer) == .success, let observer else { return }
        guard AXObserverAddNotification(observer, AXUIElementCreateApplication(pid),
                                        kAXFocusedUIElementChangedNotification as CFString,
                                        Unmanaged.passUnretained(self).toOpaque()) == .success else { return }
        focusObserver = observer
        focusLost = lost
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    func stopWatching() {
        if let observer = focusObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        focusObserver = nil
        focusLost = nil
    }

    func apply(_ next: String) throws {
        try validate()
        guard let (range, replacement) = document.replacement(for: next) else { return }
        if range != document.selection {
            guard let value = rangeValue(range),
                  AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
            else { throw Self.unavailable }
        }
        // AX has separate select and replace operations. Recheck between them.
        try verify(document.expected, selection: range)
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFString) == .success
        else { throw Self.unavailable }
        document.accept(next)
        // Some hosts leave the replacement selected. Collapse only that exact selection.
        let inserted = NSRange(location: range.location, length: replacement.utf16.count)
        if inserted.length > 0, selectedRange(element) == inserted {
            try verify(document.expected, selection: inserted)
            guard let caret = rangeValue(document.selection),
                  AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, caret) == .success
            else { throw Self.unavailable }
        }
        try validate()
    }

    /// AX coordinates are measured down from the top of the primary display.
    func bounds() -> CGRect? {
        var rect = CGRect.zero
        var result: CFTypeRef?
        let caret = NSRange(location: NSMaxRange(document.selection), length: 0)
        if let range = rangeValue(caret),
           AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &result) == .success,
           let result, CFGetTypeID(result) == AXValueGetTypeID(),
           AXValueGetValue(result as! AXValue, .cgRect, &rect), rect.height > 0 { return rect }
        guard let pos = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
              AXValueGetValue(pos as! AXValue, .cgPoint, &rect.origin),
              AXValueGetValue(size as! AXValue, .cgSize, &rect.size), rect.height > 0 else { return nil }
        return rect
    }
}
