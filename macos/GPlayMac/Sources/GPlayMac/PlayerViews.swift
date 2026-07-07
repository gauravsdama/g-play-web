import SwiftUI

struct PlayerBar: View {
    @ObservedObject var player: PlayerController
    let openNowPlaying: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: openNowPlaying) {
                HStack(spacing: 12) {
                    ArtworkView(track: player.currentTrack, size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.currentTrack?.displayTitle ?? "No track selected")
                            .font(.headline)
                            .lineLimit(1)
                        Text(player.currentTrack?.displayArtist ?? "Choose a track from Library")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 8) {
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(player.currentTrack == nil)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button {
                    player.skipNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(player.queue.isEmpty)
                .accessibilityLabel("Next track")
            }

            VStack(spacing: 5) {
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 1)
                )
                HStack {
                    Text(formattedDuration(player.currentTime))
                    Spacer()
                    Text(formattedDuration(player.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .frame(width: 320)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}

struct NowPlayingNativeView: View {
    @ObservedObject var store: GPlayStore

    var body: some View {
        AppCard {
            HStack(alignment: .top, spacing: 28) {
                ArtworkView(track: store.player.currentTrack, size: 320)

                VStack(alignment: .leading, spacing: 18) {
                    Text("Now Playing")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(store.player.currentTrack?.displayTitle ?? "No track selected")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .lineLimit(3)
                        .minimumScaleFactor(0.72)

                    Text(store.player.currentTrack?.displayArtist ?? "Pick something from Library")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    if let track = store.player.currentTrack {
                        HStack {
                            Label(track.sourceLabel, systemImage: "waveform")
                            Label(track.root.title, systemImage: track.root.symbol)
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button {
                            store.player.toggle()
                        } label: {
                            Label(store.player.isPlaying ? "Pause" : "Play", systemImage: store.player.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(store.player.currentTrack == nil)

                        Button {
                            store.player.skipNext()
                        } label: {
                            Label("Next", systemImage: "forward.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(store.player.queue.isEmpty)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { store.player.currentTime },
                                set: { store.player.seek(to: $0) }
                            ),
                            in: 0...max(store.player.duration, 1)
                        )
                        HStack {
                            Text(formattedDuration(store.player.currentTime))
                            Spacer()
                            Text(formattedDuration(store.player.duration))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }

                    QueueList(player: store.player)
                }
            }
        }
    }
}

struct QueueList: View {
    @ObservedObject var player: PlayerController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Up Next")
                    .font(.headline)
                Spacer()
                if !player.queue.isEmpty {
                    Button("Clear") {
                        player.clearQueue()
                    }
                    .buttonStyle(.borderless)
                }
            }

            if player.queue.isEmpty {
                Text("Queue is empty.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(player.queue) { track in
                    HStack {
                        ArtworkView(track: track, size: 36)
                        VStack(alignment: .leading) {
                            Text(track.displayTitle)
                                .lineLimit(1)
                            Text(track.displayArtist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            player.removeFromQueue(track)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(track.displayTitle) from queue")
                    }
                    .padding(8)
                    .background(Color.gSurface.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(.top, 8)
    }
}
