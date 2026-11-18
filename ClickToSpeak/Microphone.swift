import AVFoundation
import Accelerate
import Speech

/// The tap's buffer belongs to the engine and may be reused after the callback.
private func copyPCM(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard source.frameLength > 0,
          let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return nil }
    copy.frameLength = source.frameLength
    let from = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
    let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
    for index in from.indices {
        guard from[index].mDataByteSize <= to[index].mDataByteSize,
              let input = from[index].mData, let output = to[index].mData else { return nil }
        memcpy(output, input, Int(from[index].mDataByteSize))
        to[index].mDataByteSize = from[index].mDataByteSize
    }
    return copy
}

private func amplitude(_ buffer: AVAudioPCMBuffer) -> Double {
    guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
    var rms: Float = 0
    vDSP_rmsqv(channel, vDSP_Stride(buffer.stride), &rms, vDSP_Length(buffer.frameLength))
    return min(1, max(0, (20 * log10(Double(max(rms, 0.00001))) + 60) / 60))
}

private final class PCMConverter {
    let converter: AVAudioConverter
    let target: AVAudioFormat

    init(from: AVAudioFormat, to: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: from, to: to) else {
            throw DictationError.message("Le format du micro est incompatible.")
        }
        self.converter = converter
        self.target = to
        converter.primeMethod = .none
    }

    func convert(_ input: AVAudioPCMBuffer?) throws -> AVAudioPCMBuffer? {
        let frames = Double(input?.frameLength ?? 1024) * target.sampleRate / converter.inputFormat.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(ceil(frames)) + 64)
        else { throw DictationError.message("Le tampon audio est indisponible.") }
        var delivered = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, state in
            guard let input else { state.pointee = .endOfStream; return nil }
            guard !delivered else { state.pointee = .noDataNow; return nil }
            delivered = true
            state.pointee = .haveData
            return input
        }
        if let error { throw error }
        guard status != .error else { throw DictationError.message("La conversion audio a échoué.") }
        return out.frameLength > 0 ? out : nil
    }
}

@MainActor
final class Microphone {
    private let engine = AVAudioEngine()
    private var feed: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation?
    private var worker: Task<Void, Never>?
    private var configurationObserver: NSObjectProtocol?
    private var tapped = false

    func start(format: AVAudioFormat, destination: AsyncStream<AnalyzerInput>.Continuation,
               level: @escaping @MainActor (Double) -> Void,
               failed: @escaping @MainActor (Error) -> Void) throws {
        let node = engine.inputNode
        let hardware = node.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0,
              let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hardware.sampleRate,
                                         channels: hardware.channelCount, interleaved: false)
        else { throw DictationError.message("Aucun microphone disponible.") }
        let converter = try PCMConverter(from: source, to: format)
        let (buffers, feed) = AsyncThrowingStream<AVAudioPCMBuffer, Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        self.feed = feed
        worker = Task.detached(priority: .userInitiated) {
            defer { destination.finish() }
            func send(_ pcm: AVAudioPCMBuffer) throws {
                switch destination.yield(AnalyzerInput(buffer: pcm)) {
                case .enqueued: break
                case .terminated: throw CancellationError()
                case .dropped: throw DictationError.message("Le moteur de dictée ne suit plus le flux du micro.")
                @unknown default: throw CancellationError()
                }
            }
            do {
                var lastLevel = -Double.infinity
                for try await buffer in buffers {
                    try Task.checkCancellation()
                    if let data = try converter.convert(buffer) { try send(data) }
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - lastLevel >= 0.05 {
                        lastLevel = now
                        await level(amplitude(buffer))
                    }
                }
                try Task.checkCancellation()
                while let tail = try converter.convert(nil) { try send(tail) }
            } catch is CancellationError {
            } catch { await failed(error) }
        }
        node.installTap(onBus: 0, bufferSize: 1024, format: source, block: Self.tap(feed))
        tapped = true
        do { engine.prepare(); try engine.start() }
        catch { cancel(); throw error }
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
            object: engine, queue: .main) { _ in
                Task { @MainActor in failed(DictationError.message("Le microphone a changé. Relancez la dictée.")) }
            }
    }

    // Build the callback outside MainActor isolation: Core Audio invokes it on its own thread.
    private nonisolated static func tap(_ feed: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let owned = copyPCM(buffer) else {
                feed.finish(throwing: DictationError.message("La capture du micro a été interrompue."))
                return
            }
            if case .dropped = feed.yield(owned) {
                feed.finish(throwing: DictationError.message("Le traitement audio a pris du retard. Relancez la dictée."))
            }
        }
    }

    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if engine.isRunning { engine.stop() }
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        feed?.finish()
        feed = nil
    }

    func cancel() {
        worker?.cancel()
        stop()
        worker = nil
    }
}
