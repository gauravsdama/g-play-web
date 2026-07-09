import SwiftUI
import UniformTypeIdentifiers

struct DownloadNativeView: View {
    @ObservedObject var store: GPlayStore
    @State private var url = ""
    @State private var quality = 320
    @State private var playlist = ""
    @State private var isImportingFiles = false

    private let qualities = [96, 128, 160, 192, 256, 320]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AppCard {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Import from YouTube or SoundCloud", systemImage: "arrow.down.circle.fill")
                        .font(.title2.weight(.semibold))

                    TextField("YouTube or SoundCloud URL", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("YouTube or SoundCloud URL")

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
                            if store.statusMessage?.hasPrefix("Imported") == true {
                                url = ""
                            }
                        }
                    } label: {
                        Label(store.isLoading ? "Importing" : "Import to Library", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.isLoading)
                }
            }

            AppCard {
                HStack(spacing: 16) {
                    Label("Import local audio", systemImage: "music.note")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        isImportingFiles = true
                    } label: {
                        Label("Choose Files", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.isLoading)
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await store.importFiles(urls) }
            case .failure(let error):
                store.statusMessage = error.localizedDescription
            }
        }
    }
}

struct PlaylistsNativeView: View {
    @ObservedObject var store: GPlayStore
    @State private var newPlaylist = ""
    @State private var playlistPreset = TunePreset.all[0]

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
                        Button {
                            store.playActivePlaylist()
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.activePlaylistEntries.isEmpty)

                        Button {
                            store.addActivePlaylistToQueue()
                        } label: {
                            Label("Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.activePlaylistEntries.isEmpty)

                        Button("Add Selected Track") {
                            Task { await store.addSelectedToActivePlaylist() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.selectedTrack == nil || store.activePlaylist == nil)
                    }

                    HStack(spacing: 10) {
                        Picker("EQ preset", selection: $playlistPreset) {
                            ForEach(TunePreset.all) { preset in
                                Text(preset.id).tag(preset)
                            }
                        }
                        .frame(width: 260)

                        Button {
                            Task { await store.applyPresetToActivePlaylist(playlistPreset) }
                        } label: {
                            Label("Apply EQ", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.activePlaylistEntries.isEmpty || store.isLoading)
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
                                LibraryRow(
                                    entry: entry,
                                    root: .playlists,
                                    open: {
                                        store.select(entry.track(root: .playlists))
                                    },
                                    play: {
                                        store.play(entry.track(root: .playlists))
                                    },
                                    queue: {
                                        store.player.addToQueue(entry.track(root: .playlists))
                                    },
                                    openInFinder: {
                                        Task { await store.openFolder(root: .playlists, path: entry.path) }
                                    }
                                )
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
    @ObservedObject private var player: PlayerController
    @State private var selectedPreset = TunePreset.all[0]
    @State private var eqGains = TunePreset.all[0].eq
    @State private var preamp = TunePreset.all[0].preamp
    @State private var spatial = TunePreset.all[0].spatial
    @State private var drc = TunePreset.all[0].drc
    @State private var hasManualEdits = false
    @State private var cutStart = 0.0
    @State private var cutEnd = 0.0

    private let drcModes = ["Off", "Soft", "Medium", "High"]
    private let eqColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    init(store: GPlayStore) {
        self.store = store
        self.player = store.player
    }

    private var renderPreset: TunePreset {
        TunePreset(
            id: hasManualEdits ? "Custom EQ" : selectedPreset.id,
            preamp: preamp,
            eq: eqGains,
            spatial: spatial,
            drc: drc
        )
    }

    private var selectedDuration: Double {
        guard player.currentTrack?.id == store.selectedTrack?.id else {
            return 0
        }
        return player.duration
    }

    private var maxTrimValue: Double {
        max(selectedDuration, 1)
    }

    private var trimEnd: Double {
        cutEnd > cutStart ? cutEnd : maxTrimValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AppCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("EQ")
                                .font(.title2.weight(.semibold))
                            Text(store.selectedTrack?.displayTitle ?? "Select a track from Library")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            Task { await store.applyPreset(renderPreset) }
                        } label: {
                            Label("Render Version", systemImage: "wand.and.stars")
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
                    .frame(width: 280)
                    .onChange(of: selectedPreset) { preset in
                        loadPreset(preset)
                    }

                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Preamp")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Slider(value: editableBinding($preamp), in: -12...12, step: 0.5)
                            Text("\(preamp, specifier: "%.1f") dB")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text("Spatial")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Slider(value: editableBinding($spatial), in: 0...100, step: 1)
                            Text("\(spatial, specifier: "%.0f")%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text("Compression")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Picker("Compression", selection: editableBinding($drc)) {
                                ForEach(drcModes, id: \.self) { mode in
                                    Text(mode).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text(drc)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    LazyVGrid(columns: eqColumns, spacing: 12) {
                        ForEach(Array(eqBands.enumerated()), id: \.offset) { index, band in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(band >= 1000 ? "\(band / 1000)kHz" : "\(band)Hz")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Slider(
                                    value: Binding(
                                        get: { eqGains[index] },
                                        set: { value in
                                            eqGains[index] = value
                                            hasManualEdits = true
                                        }
                                    ),
                                    in: -12...12,
                                    step: 0.5
                                )
                                Text("\(eqGains[index], specifier: "%.1f") dB")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(Color.gSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    HStack {
                        Button {
                            loadPreset(.all[0])
                            selectedPreset = .all[0]
                        } label: {
                            Label("Reset Flat", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)

                        if hasManualEdits {
                            Label("Custom EQ will render a new version.", systemImage: "slider.horizontal.3")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            AppCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Trim")
                                .font(.title2.weight(.semibold))
                            Text(store.selectedTrack?.displayTitle ?? "Select a track from Library")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            if let track = store.selectedTrack {
                                store.play(track)
                            }
                        } label: {
                            Label("Preview Track", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.selectedTrack == nil)
                    }

                    HStack(spacing: 12) {
                        Button {
                            cutStart = min(player.currentTime, maxTrimValue)
                            if cutEnd <= cutStart {
                                cutEnd = min(maxTrimValue, cutStart + 1)
                            }
                        } label: {
                            Label("Set Start", systemImage: "arrow.left.to.line")
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedDuration <= 0)

                        Button {
                            cutEnd = max(player.currentTime, cutStart + 0.1)
                        } label: {
                            Label("Set End", systemImage: "arrow.right.to.line")
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedDuration <= 0)

                        Text("\(formattedDuration(cutStart)) - \(formattedDuration(trimEnd))")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Slider(value: $cutStart, in: 0...maxTrimValue, step: 0.1)
                            .disabled(selectedDuration <= 0)
                            .onChange(of: cutStart) { value in
                                if value >= trimEnd {
                                    cutEnd = min(maxTrimValue, value + 1)
                                }
                            }
                        Slider(value: $cutEnd, in: 0...maxTrimValue, step: 0.1)
                            .disabled(selectedDuration <= 0)
                            .onChange(of: cutEnd) { value in
                                if value <= cutStart {
                                    cutStart = max(0, value - 1)
                                }
                            }
                    }

                    Button {
                        Task { await store.applyCut(start: cutStart, end: trimEnd) }
                    } label: {
                        Label("Render Cut", systemImage: "scissors")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.selectedTrack == nil || selectedDuration <= 0 || trimEnd <= cutStart || store.isLoading)
                }
            }
        }
        .onChange(of: store.selectedTrack) { _ in
            cutStart = 0
            cutEnd = 0
        }
        .onChange(of: selectedDuration) { value in
            if value > 0, cutEnd == 0 {
                cutEnd = value
            }
        }
    }

    private func loadPreset(_ preset: TunePreset) {
        eqGains = preset.eq
        preamp = preset.preamp
        spatial = preset.spatial
        drc = preset.drc
        hasManualEdits = false
    }

    private func editableBinding(_ value: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = newValue
                hasManualEdits = true
            }
        )
    }

    private func editableBinding(_ value: Binding<String>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = newValue
                hasManualEdits = true
            }
        )
    }
}

struct PartyNativeView: View {
    @ObservedObject var store: GPlayStore
    @State private var url = ""
    @State private var quality = 320

    private let qualities = [96, 128, 160, 192, 256, 320]

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.partyActive ? "Party \(store.partyCode ?? "")" : "Party")
                            .font(.title2.weight(.semibold))
                        Text("\(store.partyQueue.count) queued")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.partyActive {
                        Button {
                            Task { await store.refreshPartyQueue() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            Task { await store.stopParty() }
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            Task { await store.startParty() }
                        } label: {
                            Label("Start", systemImage: "person.2.wave.2")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if store.partyActive {
                    HStack(spacing: 12) {
                        TextField("YouTube or SoundCloud URL", text: $url)
                            .textFieldStyle(.roundedBorder)
                        Picker("Quality", selection: $quality) {
                            ForEach(qualities, id: \.self) { value in
                                Text("\(value)k").tag(value)
                            }
                        }
                        .frame(width: 130)
                        Button {
                            Task {
                                await store.enqueuePartyURL(url, quality: quality)
                                if store.statusMessage?.hasPrefix("Added") == true {
                                    url = ""
                                }
                            }
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isLoading)
                    }

                    if store.partyQueue.isEmpty {
                        EmptyStateView(
                            title: "No party tracks",
                            systemImage: "person.2.wave.2",
                            description: "Start with a URL above."
                        )
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(store.partyQueue) { item in
                                HStack(spacing: 12) {
                                    ArtworkView(track: item.track, size: 44)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.track.displayTitle)
                                            .lineLimit(1)
                                        Text(item.track.displayArtist)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Button {
                                        store.play(item.track)
                                    } label: {
                                        Image(systemName: "play.fill")
                                    }
                                    .buttonStyle(.borderless)

                                    Button {
                                        store.player.addToQueue(item.track)
                                    } label: {
                                        Image(systemName: "text.line.last.and.arrowtriangle.forward")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(10)
                                .background(Color.gSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
        .task {
            if store.partyActive {
                await store.refreshPartyQueue()
            }
        }
    }
}

struct VisualizerNativeView: View {
    @ObservedObject var player: PlayerController
    @State private var selectedPreset = VisualizerPreset.all[0]

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Visualiser")
                            .font(.title2.weight(.semibold))
                        Text(player.currentTrack?.displayTitle ?? "Play a track to animate the canvas")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(player.isPlaying ? "Playing" : "Idle", systemImage: player.isPlaying ? "waveform" : "pause.circle")
                        .foregroundStyle(.secondary)
                }

                Picker("Preset", selection: $selectedPreset) {
                    ForEach(VisualizerPreset.all) { preset in
                        Label(preset.title, systemImage: preset.symbol)
                            .tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let signal = VisualizerSignal.make(
                            track: player.currentTrack,
                            wallTime: time,
                            playhead: player.currentTime,
                            isPlaying: player.isPlaying
                        )
                        VisualizerRenderer.draw(
                            preset: selectedPreset,
                            signal: signal,
                            context: &context,
                            size: size,
                            time: time
                        )
                    }
                }
                .frame(height: 460)
                .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("\(selectedPreset.title) audio visualiser")
            }
        }
    }
}
