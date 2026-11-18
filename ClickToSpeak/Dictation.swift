import AppKit
import ApplicationServices
import AVFoundation
import CoreMedia
import Speech

enum PrivacyPane: String {
    case microphone = "Privacy_Microphone"
    case accessibility = "Privacy_Accessibility"

    @MainActor func open() {
        if self == .accessibility && !AXIsProcessTrusted() {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + rawValue) {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
private final class Session {
    enum Phase { case preparing, listening, finishing }
    var phase = Phase.preparing
    let field: FocusedField
    let anchor: CGRect?
    let mic = Microphone()
    var transcript = Transcript()
    var analyzer: SpeechAnalyzer?
    var startup: Task<Void, Never>?
    var results: Task<Void, Never>?
    var monitor: Task<Void, Never>?
    var finish: Task<Void, Never>?
    var timeout: Task<Void, Never>?
    var applicationObserver: NSObjectProtocol?
    var input: AsyncStream<AnalyzerInput>.Continuation?

    init(_ field: FocusedField) { self.field = field; anchor = field.bounds() }
}

@MainActor
final class Dictation {
    private let panel = FloatingPanel()
    private var active: Session?
    private var dismiss: Task<Void, Never>?

    func trigger(pid: pid_t?) {
        if active != nil { terminate(); return }
        dismiss?.cancel()
        guard AXIsProcessTrusted() else {
            notice("Autorisez l’accès Accessibilité pour insérer la dictée dans le champ actif.", settings: .accessibility)
            return
        }
        do {
            guard let pid else { throw DictationError.message("Placez le curseur dans un champ de texte.") }
            let session = Session(try FocusedField.capture(pid: pid))
            active = session
            display("Préparation du micro…", session)
            session.startup = Task { [weak self, weak session] in
                guard let self, let session else { return }
                do { try await self.prepare(session) }
                catch { self.failed(error, session) }
            }
        } catch { notice(error.localizedDescription) }
    }

    private func check(_ s: Session) throws {
        guard active === s, !Task.isCancelled else { throw CancellationError() }
        try s.field.validate()
    }

    private func display(_ title: String, _ s: Session, listening: Bool = false) {
        panel.show(title, near: s.anchor, listening: listening) { [weak self] in self?.terminate() }
    }

    private func prepare(_ s: Session) async throws {
        try check(s)
        var permission = AVCaptureDevice.authorizationStatus(for: .audio)
        if permission == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            permission = AVCaptureDevice.authorizationStatus(for: .audio)
        }
        guard active === s else { return }
        guard permission == .authorized else {
            clear(s)
            notice("Autorisez le microphone pour dicter, puis relancez ClickToSpeak dans le champ.", settings: .microphone)
            return
        }
        try check(s)
        let lostFocus = { [weak self, weak s] in
            guard let self, let s, self.active === s else { return }
            self.failed(DictationError.message("Dictée arrêtée. Le champ actif a changé."), s)
        }
        s.field.watchFocus(lostFocus)
        let originalPID = s.field.pid
        s.applicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != originalPID else { return }
            MainActor.assumeIsolated { lostFocus() }
        }
        s.monitor = Task { [weak self, weak s] in
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(180))
                    guard let self, let s, self.active === s else { return }
                    do { try s.field.validate() }
                    catch { self.failed(error, s); return }
                }
            } catch {}
        }
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "fr-FR"))
        else { throw DictationError.message("La dictée française est indisponible sur ce Mac.") }
        let module = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                       reportingOptions: [.volatileResults], attributeOptions: [])
        if !(await AssetInventory.reservedLocales).contains(locale) {
            _ = try await AssetInventory.reserve(locale: locale)
        }
        let status = await AssetInventory.status(forModules: [module])
        try check(s)
        switch status {
        case .installed: break
        case .supported, .downloading:
            display("Préparation de la dictée française", s)
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                    try check(s)
                    try await request.downloadAndInstall()
                }
            } catch {
                throw DictationError.message("Installation du français interrompue. Vérifiez la connexion, puis relancez la dictée.")
            }
        default: throw DictationError.message("Le modèle de français est indisponible.")
        }
        try check(s)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw DictationError.message("Le modèle de français ne fournit aucun format audio compatible.")
        }
        try check(s)
        let analyzer = SpeechAnalyzer(modules: [module])
        s.analyzer = analyzer
        try await analyzer.prepareToAnalyze(in: format)
        try check(s)
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(64))
        s.input = input
        s.results = Task { [weak self, weak s] in
            do {
                for try await result in module.results {
                    guard let self, let s, self.active === s else { return }
                    s.transcript.receive(String(result.text.characters), end: CMTimeGetSeconds(CMTimeRangeGetEnd(result.range)),
                                         final: result.isFinal)
                    try s.field.apply(s.transcript.text)
                }
                if let self, let s, self.active === s, s.phase != .finishing {
                    self.failed(DictationError.message("Le moteur de dictée s’est arrêté."), s)
                }
            } catch {
                if let self, let s { self.failed(error, s) }
            }
        }
        try await analyzer.start(inputSequence: stream)
        try check(s)
        try s.mic.start(format: format, destination: input) { [weak self, weak s] value in
            guard let self, let s, self.active === s, s.phase == .listening else { return }
            self.panel.state.push(value)
        } failed: { [weak self, weak s] error in
            if let self, let s { self.failed(error, s) }
        }
        s.phase = .listening
        display("Écoute en cours", s, listening: true)
    }

    func terminate() {
        guard let s = active else { return }
        if s.phase == .preparing { clear(s); return }
        guard s.phase == .listening, let analyzer = s.analyzer else { return }
        s.phase = .finishing
        s.mic.stop() // Finish the stream after the converter has drained captured buffers.
        do { try s.field.validate() } catch { failed(error, s); return }
        display("Finalisation…", s)
        s.timeout = Task { [weak self, weak s] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            if let self, let s { self.failed(DictationError.message("Finalisation interrompue. Le texte affiché est conservé."), s) }
        }
        s.finish = Task { [weak self, weak s] in
            guard let self, let s else { return }
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                await s.results?.value
                if self.active === s { self.clear(s, finished: true) }
            } catch { self.failed(error, s) }
        }
    }

    private func failed(_ error: Error, _ s: Session) {
        guard active === s else { return }
        clear(s)
        notice((error as? DictationError)?.localizedDescription ?? "Dictée interrompue. Vérifiez le microphone puis réessayez.")
    }

    private func clear(_ s: Session, finished: Bool = false) {
        guard active === s else { return }
        active = nil
        s.field.stopWatching()
        if let observer = s.applicationObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        s.applicationObserver = nil
        s.mic.cancel()
        s.input?.finish()
        s.monitor?.cancel()
        s.startup?.cancel()
        s.results?.cancel()
        s.finish?.cancel()
        s.timeout?.cancel()
        if !finished, let analyzer = s.analyzer { Task { await analyzer.cancelAndFinishNow() } }
        panel.hide()
    }

    func shutdown() {
        dismiss?.cancel()
        if let active { clear(active) }
        panel.hide()
    }

    func notice(_ title: String, settings: PrivacyPane? = nil) {
        dismiss?.cancel()
        panel.show(title, near: nil, button: settings == nil ? "Fermer" : "Réglages…") { [weak self] in
            self?.panel.hide()
            settings?.open()
        }
        dismiss = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(settings == nil ? 6 : 18)) } catch { return }
            self?.panel.hide()
        }
    }
}
