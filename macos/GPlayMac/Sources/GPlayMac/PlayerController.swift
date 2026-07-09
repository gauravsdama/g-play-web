import AVFoundation
import Foundation

@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var queue: [Track] = []
    @Published var history: [Track] = []

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

    func play(_ track: Track, fromHistory: Bool = false) {
        if let currentTrack, currentTrack.id != track.id, !fromHistory {
            history.append(currentTrack)
        }
        currentTrack = track
        currentTime = 0
        duration = 0
        player.replaceCurrentItem(with: AVPlayerItem(url: api.fileURL(for: track)))
        player.play()
        isPlaying = true
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentTrack = nil
        currentTime = 0
        duration = 0
        isPlaying = false
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

    func skipBack() {
        guard currentTrack != nil else {
            return
        }
        if currentTime > 2 {
            seek(to: 0)
            return
        }
        guard let previous = history.popLast() else {
            seek(to: 0)
            return
        }
        play(previous, fromHistory: true)
    }

    func clearQueue() {
        queue.removeAll()
    }

    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index) else {
            return
        }
        queue.remove(at: index)
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
