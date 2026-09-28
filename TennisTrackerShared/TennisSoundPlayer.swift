import AVFoundation
import Foundation

@MainActor
final class TennisSoundPlayer {
    static let shared = TennisSoundPlayer()
    private var player: AVAudioPlayer?
    private var releaseTask: Task<Void, Never>?
    private var lastFeedback = Date.distantPast

    func feedback(_ event: TennisFeedbackEvent, settings: TennisSoundSettings) {
        guard settings.allows(event), Date().timeIntervalSince(lastFeedback) >= 2 else { return }
        if play(settings.selected, volume: 0.35) { lastFeedback = Date() }
    }

    @discardableResult
    func preview(_ sound: TennisSound) -> Bool { play(sound, volume: 0.65) }

    private func play(_ sound: TennisSound, volume: Float) -> Bool {
        stop()
        guard let url = Bundle.main.url(forResource: sound.filename, withExtension: nil) else { return false }
        do {
            // Nonessential audio mixes with speech/music and respects silent mode.
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let next = try AVAudioPlayer(contentsOf: url)
            next.volume = volume
            next.prepareToPlay()
            guard next.play() else { stop(); return false }
            player = next
            releaseTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((next.duration + 0.1) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
            return true
        } catch { stop(); return false }
    }

    func stop() {
        releaseTask?.cancel()
        releaseTask = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
