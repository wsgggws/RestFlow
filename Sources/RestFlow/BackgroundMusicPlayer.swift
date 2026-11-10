import AVFoundation
import RestFlowCore

/// Keeps playback independent of window count and preserves the playhead on pause.
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
    static func alertURL(_ id: String) -> URL? {
        Bundle.main.url(forResource: "alert-\(id)", withExtension: "wav", subdirectory: "Audio")
    }
    static func musicURL(_ id: String) -> URL? {
        Bundle.main.url(forResource: "ambient-\(id)", withExtension: "wav", subdirectory: "Audio")
    }
}

@MainActor
final class BackgroundMusicPlayer {
    private var output: (any LoopAudioOutput)?
    private var currentURL: URL?
    private var failure: String?
    private let makeOutput: (URL) throws -> any LoopAudioOutput

    init(makeOutput: ((URL) throws -> any LoopAudioOutput)? = nil) {
        self.makeOutput = makeOutput ?? { try AVLoopOutput(url: $0) }
    }

    @discardableResult
    func sync(url: URL?, volume: Double, running: Bool) -> String? {
        guard let url, volume > 0 else { stop(); return nil }
        if url != currentURL {
            stop()
            currentURL = url
            do { output = try makeOutput(url) }
            catch { failure = error.localizedDescription }
        }
        output?.volume = Float(volume)
        if running {
            if output?.isPlaying == false { output?.play() }
        } else if output?.isPlaying == true { output?.pause() }
        return failure
    }

    func stop() {
        output?.stop()
        output = nil
        currentURL = nil
        failure = nil
    }
}
