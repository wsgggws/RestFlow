import AVFoundation
import AudioToolbox
import RestFlowCore

@MainActor
protocol LoopAudioOutput: AnyObject {
    var volume: Float { get set }
    var isPlaying: Bool { get }
    func play() throws
    func pause()
    func stop()
}

/// A shared engine places the peak limiter after every layer, before the device output.
/// Offline rendering uses the identical graph so mix gain and clipping have a measurable regression test.
@MainActor
final class NoiseAudioGraph {
    let engine = AVAudioEngine()
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))

    init(offline: Bool = false) throws {
        // AVAudioMixerNode centers mono sources at -3 dB; restore that gain before limiting.
        let status = AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, 3.0103, 0)
        guard status == noErr else { throw ConfigurationError.invalid("Unable to configure focus audio limiter") }
        engine.attach(limiter)
        engine.connect(engine.mainMixerNode, to: limiter, format: format)
        engine.connect(limiter, to: engine.outputNode, format: format)
        if offline { try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096) }
    }

    func output(url: URL) throws -> any LoopAudioOutput { try EngineLoopOutput(url: url, graph: self) }
    func pause() { if engine.isRunning { engine.pause() } }
    func stop() { engine.stop() }
}

@MainActor
private final class EngineLoopOutput: LoopAudioOutput {
    private let graph: NoiseAudioGraph
    private let player = AVAudioPlayerNode()
    // scheduleBuffer retains audio until stop; keep it here to make ownership explicit across pause.
    private let buffer: AVAudioPCMBuffer
    private var attached = true

    init(url: URL, graph: NoiseAudioGraph) throws {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.length <= AVAudioFramePosition(44100 * 60),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw ConfigurationError.invalid("Invalid focus noise buffer")
        }
        try file.read(into: buffer)
        self.graph = graph; self.buffer = buffer
        graph.engine.attach(player)
        graph.engine.connect(player, to: graph.engine.mainMixerNode, format: buffer.format)
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
    }
    var volume: Float { get { player.volume } set { player.volume = newValue } }
    var isPlaying: Bool { player.isPlaying && graph.engine.isRunning }
    func play() throws {
        if !graph.engine.isRunning { try graph.engine.start() }
        player.play()
    }
    func pause() { player.pause() }
    func stop() {
        guard attached else { return }
        player.stop(); graph.engine.detach(player); attached = false
    }
}

enum AudioAssets {
    static func noiseURL(_ id: String) -> URL? {
        guard FocusNoise(rawValue: id) != nil else { return nil }
        return Bundle.main.url(forResource: "noise-\(id)", withExtension: "wav", subdirectory: "Audio")
    }
}

@MainActor
final class FocusNoisePlayer {
    private var outputs: [String: any LoopAudioOutput] = [:]
    private var failures: [String: String] = [:]
    private let makeOutput: ((URL) throws -> any LoopAudioOutput)?
    private var graph: NoiseAudioGraph?

    init(makeOutput: ((URL) throws -> any LoopAudioOutput)? = nil, graph: NoiseAudioGraph? = nil) {
        self.makeOutput = makeOutput; self.graph = graph
    }

    /// Equal-power layers retain perceived loudness as the mix grows. The shared limiter catches peaks.
    static func layerVolume(_ volume: Double, count: Int) -> Float {
        Float(sqrt(max(0, min(1, volume))) / sqrt(Double(max(1, count))))
    }

    @discardableResult
    func sync(ids: [String], volume: Double, running: Bool) -> String? {
        let desired = Set(ids)
        for id in Array(outputs.keys) where !desired.contains(id) { outputs.removeValue(forKey: id)?.stop() }
        failures = failures.filter { desired.contains($0.key) }
        if running && volume > 0 {
            for id in ids where outputs[id] == nil && failures[id] == nil {
                do {
                    guard let url = AudioAssets.noiseURL(id) else { throw ConfigurationError.invalid("Missing noise: \(id)") }
                    if let makeOutput { outputs[id] = try makeOutput(url) }
                    else {
                        if graph == nil { graph = try NoiseAudioGraph() }
                        outputs[id] = try graph!.output(url: url)
                    }
                } catch { failures[id] = "\(id): \(error.localizedDescription)" }
            }
        }
        // Failed decoders do not reduce the loudness of healthy layers.
        let channelVolume = Self.layerVolume(volume, count: outputs.count)
        for (id, output) in outputs {
            output.volume = channelVolume
            if running && volume > 0 && failures[id] == nil {
                if !output.isPlaying {
                    do { try output.play() }
                    catch { failures[id] = "\(id): \(error.localizedDescription)" }
                }
            } else if output.isPlaying { output.pause() }
        }
        if !outputs.values.contains(where: \.isPlaying) { graph?.pause() }
        return failures.keys.sorted().first.flatMap { failures[$0] }
    }

    func stop() {
        outputs.values.forEach { $0.stop() }
        outputs.removeAll(); failures.removeAll(); graph?.stop()
    }
}
