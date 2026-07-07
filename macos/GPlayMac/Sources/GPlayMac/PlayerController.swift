import AVFoundation
import Foundation

@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var queue: [Track] = []

    private let api: GPlayAPI
    private let player = AVPlayer()
    private var timer: Timer?

    init(api: GPlayAPI) {
        self.api = api
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncTime()
            }
        }
    }

    func play(_ track: Track) {
        currentTrack = track
        currentTime = 0
        duration = 0
        player.replaceCurrentItem(with: AVPlayerItem(url: api.fileURL(for: track)))
        player.play()
        isPlaying = true
    }

    func toggle() {
        guard currentTrack != nil else {
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func addToQueue(_ track: Track) {
        queue.append(track)
    }

    func playNext(_ track: Track) {
        queue.insert(track, at: 0)
    }

    func skipNext() {
        guard !queue.isEmpty else {
            return
        }
        let next = queue.removeFirst()
        play(next)
    }

    func clearQueue() {
        queue.removeAll()
    }

    func removeFromQueue(_ track: Track) {
        queue.removeAll { $0.id == track.id }
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time)
        currentTime = seconds
    }

    private func syncTime() {
        currentTime = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
        if let item = player.currentItem {
            let itemDuration = item.duration.seconds
            duration = itemDuration.isFinite ? itemDuration : 0
        }
        if isPlaying, duration > 0, currentTime >= duration - 0.2 {
            isPlaying = false
            skipNext()
        }
    }
}
