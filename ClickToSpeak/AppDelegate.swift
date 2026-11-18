import AppKit
import ApplicationServices
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let dictation = Dictation()
    private var item: NSStatusItem?
    private lazy var hotKey = HotKey { [weak self] in self?.trigger() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "ClickToSpeak")
        item.button?.toolTip = "ClickToSpeak"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        if !hotKey.install() {
            dictation.notice("Raccourci indisponible. Choisissez-en un autre dans la barre des menus.")
        }
    }

    @objc(startDictation:userData:error:)
    func startDictation(_ pasteboard: NSPasteboard, userData: String?,
                        error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        // Let the host dismiss its Services menu before asking it for the focused element.
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        DispatchQueue.main.async { self.dictation.trigger(pid: pid) }
    }

    private func trigger() {
        dictation.trigger(pid: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let shortcuts = NSMenu()
        for (i, choice) in Shortcut.choices.enumerated() {
            let row = shortcuts.addItem(withTitle: choice.label, action: #selector(selectShortcut(_:)), keyEquivalent: "")
            row.target = self
            row.tag = i
            row.state = hotKey.selected == i ? .on : .off
        }
        let shortcut = menu.addItem(withTitle: "Raccourci clavier", action: nil, keyEquivalent: "")
        shortcut.submenu = shortcuts
        menu.addItem(.separator())
        let ax = AXIsProcessTrusted() ? "autorisé" : "à autoriser"
        menu.addItem(withTitle: "Accessibilité · " + ax, action: #selector(openAccessibility), keyEquivalent: "").target = self
        let mic: String
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: mic = "autorisé"
        case .notDetermined: mic = "non demandé"
        case .restricted: mic = "restreint"
        default: mic = "refusé"
        }
        menu.addItem(withTitle: "Microphone · " + mic, action: #selector(openMicrophone), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter ClickToSpeak", action: #selector(quit), keyEquivalent: "q").target = self
    }

    @objc private func selectShortcut(_ sender: NSMenuItem) {
        if !hotKey.choose(sender.tag) {
            dictation.notice("Ce raccourci est indisponible. Essayez une autre combinaison.")
        }
    }
    @objc private func openAccessibility() { PrivacyPane.accessibility.open() }
    @objc private func openMicrophone() { PrivacyPane.microphone.open() }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        dictation.shutdown()
        hotKey.uninstall()
    }
}
