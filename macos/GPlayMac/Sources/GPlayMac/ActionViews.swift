import SwiftUI

struct DownloadNativeView: View {
    @ObservedObject var store: GPlayStore
    @State private var url = ""
    @State private var quality = 320
    @State private var playlist = ""

    private let qualities = [96, 128, 160, 192, 256, 320]

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 18) {
                Label("Download from YouTube", systemImage: "arrow.down.circle.fill")
                    .font(.title2.weight(.semibold))

                TextField("YouTube URL or video ID", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("YouTube URL or video ID")

                HStack(spacing: 14) {
                    Picker("Quality", selection: $quality) {
                        ForEach(qualities, id: \.self) { value in
                            Text("\(value)k").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Playlist", selection: $playlist) {
                        Text("Library only").tag("")
                        ForEach(store.playlists, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .frame(width: 220)
                }

                Button {
                    Task {
                        await store.download(url: url, playlist: playlist, quality: quality)
                        if store.statusMessage?.hasPrefix("Downloaded") == true {
                            url = ""
                        }
                    }
                } label: {
                    Label(store.isLoading ? "Downloading" : "Download to Library", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isLoading)
            }
        }
    }
}

struct PlaylistsNativeView: View {
    @ObservedObject var store: GPlayStore
    @State private var newPlaylist = ""

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            AppCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Playlists")
                        .font(.title2.weight(.semibold))

                    HStack {
                        TextField("New playlist", text: $newPlaylist)
                            .textFieldStyle(.roundedBorder)
                        Button("Create") {
                            Task {
                                await store.createPlaylist(newPlaylist)
                                newPlaylist = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Divider()

                    if store.playlists.isEmpty {
                        Text("No playlists yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.playlists, id: \.self) { name in
                            Button {
                                Task { await store.openPlaylist(name) }
                            } label: {
                                HStack {
                                    Image(systemName: "music.note.list")
                                    Text(name)
                                    Spacer()
                                    if store.activePlaylist == name {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .buttonStyle(SourceButtonStyle(isSelected: store.activePlaylist == name))
                        }
                    }
                }
            }
            .frame(width: 340)

            AppCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(store.activePlaylist ?? "Select a playlist")
                                .font(.title2.weight(.semibold))
                            Text("\(store.activePlaylistEntries.count) tracks")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Add Selected Track") {
                            Task { await store.addSelectedToActivePlaylist() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.selectedTrack == nil || store.activePlaylist == nil)
                    }

                    if store.activePlaylistEntries.isEmpty {
                        EmptyStateView(
                            title: "No tracks",
                            systemImage: "music.note.list",
                            description: "Select a playlist or add a track."
                        )
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(store.activePlaylistEntries) { entry in
                                LibraryRow(entry: entry, root: .playlists) {
                                    store.select(entry.track(root: .playlists))
                                } play: {
                                    store.play(entry.track(root: .playlists))
                                } queue: {
                                    store.player.addToQueue(entry.track(root: .playlists))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct TuningNativeView: View {
    @ObservedObject var store: GPlayStore
    @State private var selectedPreset = TunePreset.all[0]

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Audio Tuning")
                            .font(.title2.weight(.semibold))
                        Text(store.selectedTrack?.displayTitle ?? "Select a track from Library")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        Task { await store.applyPreset(selectedPreset) }
                    } label: {
                        Label("Render Preset", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.selectedTrack == nil || store.isLoading)
                }

                Picker("Preset", selection: $selectedPreset) {
                    ForEach(TunePreset.all) { preset in
                        Text(preset.id).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                    ForEach(Array(eqBands.enumerated()), id: \.offset) { index, band in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(band >= 1000 ? "\(band / 1000)kHz" : "\(band)Hz")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Gauge(value: selectedPreset.eq[index] + 12, in: 0...24) {
                                EmptyView()
                            }
                            .gaugeStyle(.accessoryLinearCapacity)
                            Text("\(selectedPreset.eq[index], specifier: "%.1f") dB")
                                .font(.caption.monospacedDigit())
                        }
                        .padding(12)
                        .background(Color.gSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }
}

struct VisualizerNativeView: View {
    @ObservedObject var player: PlayerController

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Visualizer")
                            .font(.title2.weight(.semibold))
                        Text(player.currentTrack?.displayTitle ?? "Play a track to animate the canvas")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(player.isPlaying ? "Playing" : "Idle", systemImage: player.isPlaying ? "waveform" : "pause.circle")
                        .foregroundStyle(.secondary)
                }

                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let columns = 56
                        let spacing: CGFloat = 4
                        let width = (size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
                        let base = timeline.date.timeIntervalSinceReferenceDate

                        for index in 0..<columns {
                            let phase = base * (player.isPlaying ? 2.4 : 0.35) + Double(index) * 0.38
                            let amplitude = 0.18 + 0.72 * abs(sin(phase))
                            let height = size.height * amplitude
                            let x = CGFloat(index) * (width + spacing)
                            let y = (size.height - height) / 2
                            let rect = CGRect(x: x, y: y, width: width, height: height)
                            let color = Color.gAccent.opacity(0.35 + 0.45 * amplitude)
                            context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(color))
                        }
                    }
                }
                .frame(height: 420)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
                .accessibilityLabel("Audio visualizer")
            }
        }
    }
}
