import AVFoundation
import RestFlowCore

@MainActor
protocol LoopAudioOutput: AnyObject {
    var volume: Float { get set }
    var isPlaying: Bool { get }
    func play()
    func pause()
    func stop()
}

@MainActor
private final class AVLoopOutput: LoopAudioOutput {
    private let player: AVAudioPlayer
    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        player.numberOfLoops = -1
        player.prepareToPlay()
    }
    var volume: Float { get { player.volume } set { player.volume = newValue } }
    var isPlaying: Bool { player.isPlaying }
    func play() { player.play() }
    func pause() { player.pause() }
    func stop() { player.stop() }
}

enum AudioAssets {
    static func noiseURL(_ id: String) -> URL? {
        guard FocusNoise(rawValue: id) != nil else { return nil }
        return Bundle.main.url(forResource: "noise-\(id)", withExtension: "wav", subdirectory: "Audio")
    }
}

/// One mixer for the app, independent of displays. Unchanged layers retain their playheads.
@MainActor
final class FocusNoisePlayer {
    private var outputs: [String: any LoopAudioOutput] = [:]
    private var failures: [String: String] = [:]
    private let makeOutput: (URL) throws -> any LoopAudioOutput

    init(makeOutput: ((URL) throws -> any LoopAudioOutput)? = nil) {
        self.makeOutput = makeOutput ?? { try AVLoopOutput(url: $0) }
    }

    @discardableResult
    func sync(ids: [String], volume: Double, running: Bool) -> String? {
        let desired = Set(ids)
        for id in Array(outputs.keys) where !desired.contains(id) {
            outputs.removeValue(forKey: id)?.stop()
        }
        failures = failures.filter { desired.contains($0.key) }
        // Do not decode new files while disabled, paused, previewing, or at zero volume.
        if running && volume > 0 {
            for id in ids where outputs[id] == nil && failures[id] == nil {
                do {
                    guard let url = AudioAssets.noiseURL(id) else { throw ConfigurationError.invalid("Missing noise: \(id)") }
                    outputs[id] = try makeOutput(url)
                } catch { failures[id] = "\(id): \(error.localizedDescription)" }
            }
        }
        let channelVolume = Float(max(0, min(1, volume)) / Double(max(1, desired.count)))
        for output in outputs.values {
            output.volume = channelVolume
            if running && volume > 0 {
                if !output.isPlaying { output.play() }
            } else if output.isPlaying { output.pause() }
        }
        return failures.keys.sorted().first.flatMap { failures[$0] }
    }

    func stop() {
        outputs.values.forEach { $0.stop() }
        outputs.removeAll(); failures.removeAll()
    }
}
