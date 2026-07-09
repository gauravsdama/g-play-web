import SwiftUI

struct PlayerBar: View {
    @ObservedObject var player: PlayerController
    let selectedTrack: Track?
    let playSelected: () -> Void
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
                    player.skipBack()
                } label: {
                    Image(systemName: "backward.fill")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(player.currentTrack == nil)
                .accessibilityLabel("Previous track")

                Button {
                    playOrToggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(player.currentTrack == nil && selectedTrack == nil)
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

    private func playOrToggle() {
        if let selectedTrack, player.currentTrack?.id != selectedTrack.id {
            playSelected()
            return
        }

        player.toggle()
    }
}

struct NowPlayingNativeView: View {
    @ObservedObject var store: GPlayStore
    @ObservedObject private var player: PlayerController
    @State private var renameValue = ""
    @State private var playlistTarget = ""

    init(store: GPlayStore) {
        self.store = store
        self.player = store.player
    }

    var body: some View {
        AppCard {
            HStack(alignment: .top, spacing: 28) {
                ArtworkView(track: player.currentTrack, size: 320)

                VStack(alignment: .leading, spacing: 18) {
                    Text("Now Playing")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(player.currentTrack?.displayTitle ?? "No track selected")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .lineLimit(3)
                        .minimumScaleFactor(0.72)

                    Text(player.currentTrack?.displayArtist ?? "Pick something from Library")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    if let track = player.currentTrack {
                        HStack {
                            Label(track.sourceLabel, systemImage: "waveform")
                            Label(track.root.title, systemImage: track.root.symbol)
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button {
                            player.skipBack()
                        } label: {
                            Label("Back", systemImage: "backward.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(player.currentTrack == nil)

                        Button {
                            playOrToggle()
                        } label: {
                            Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(player.currentTrack == nil && store.selectedTrack == nil)

                        Button {
                            player.skipNext()
                        } label: {
                            Label("Next", systemImage: "forward.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(player.queue.isEmpty)
                    }

                    if let track = actionTrack {
                        HStack(spacing: 10) {
                            Button {
                                store.selectedTrack = track
                                store.selectedSection = .visualizer
                            } label: {
                                Label("Visualiser", systemImage: "waveform.path.ecg")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                store.selectedTrack = track
                                store.selectedSection = .tuning
                            } label: {
                                Label("EQ", systemImage: "slider.horizontal.3")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                Task { await store.openFolder(root: track.root, path: track.path) }
                            } label: {
                                Label("Finder", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)

                            if track.root == .edited {
                                Button {
                                    Task { await store.saveToLibrary(track: track) }
                                } label: {
                                    Label("Save to Library", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.bordered)
                            }

                            if track.root == .library || track.root == .edited {
                                Button(role: .destructive) {
                                    Task { await store.delete(track: track) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        HStack(spacing: 10) {
                            TextField("Rename file", text: $renameValue)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 320)
                            Button {
                                Task { await store.rename(track: track, newName: renameValue) }
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)
                            .disabled(renameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if !store.playlists.isEmpty {
                                Picker("Playlist", selection: $playlistTarget) {
                                    Text("Add to playlist").tag("")
                                    ForEach(store.playlists, id: \.self) { name in
                                        Text(name).tag(name)
                                    }
                                }
                                .frame(width: 210)

                                Button {
                                    Task { await store.addToPlaylist(playlistTarget, track: track) }
                                } label: {
                                    Label("Add", systemImage: "plus")
                                }
                                .buttonStyle(.bordered)
                                .disabled(playlistTarget.isEmpty)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
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

                    QueueList(player: player)
                }
            }
        }
        .onAppear {
            syncRenameValue()
        }
        .onChange(of: player.currentTrack) { _ in
            syncRenameValue()
        }
        .onChange(of: store.selectedTrack) { _ in
            syncRenameValue()
        }
    }

    private func playOrToggle() {
        if let selectedTrack = store.selectedTrack, player.currentTrack?.id != selectedTrack.id {
            store.play(selectedTrack)
            return
        }

        player.toggle()
    }

    private var actionTrack: Track? {
        player.currentTrack ?? store.selectedTrack
    }

    private func syncRenameValue() {
        renameValue = actionTrack?.displayTitle ?? ""
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
                ForEach(Array(player.queue.enumerated()), id: \.offset) { index, track in
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
                            player.removeFromQueue(at: index)
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
