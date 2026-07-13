import AppKit
import Foundation

@MainActor
final class VantabeatStore: ObservableObject {
    let api: VantabeatAPI
    let player: PlayerController
    let dataRootURL: URL?

    @Published var selectedSection: AppSection = .library
    @Published var selectedRoot: RootName = .library
    @Published var currentPath = ""
    @Published var entries: [TreeEntry] = []
    @Published var selectedTrack: Track?
    @Published var playlists: [String] = []
    @Published var librarySort: LibrarySort = .recent
    @Published var activePlaylist: String?
    @Published var activePlaylistEntries: [TreeEntry] = []
    @Published var libraryTracks: [TreeEntry] = []
    @Published var partyActive = false
    @Published var partyCode: String?
    @Published var partyQueue: [PartyItem] = []
    @Published var statusMessage: String?
    @Published var isLoading = false

    init(baseURL: URL, apiToken: String, dataRootURL: URL?) {
        self.api = VantabeatAPI(baseURL: baseURL, apiToken: apiToken)
        self.player = PlayerController(api: self.api)
        self.dataRootURL = dataRootURL
    }

    func start() async {
        await reloadAll()
    }

    func reloadAll() async {
        await loadBrowser()
        await loadPlaylists()
        await loadLibraryTracks()
    }

    func changeRoot(_ root: RootName) async {
        selectedRoot = root
        currentPath = ""
        await loadBrowser()
    }

    func openPath(_ path: String) async {
        currentPath = path
        await loadBrowser()
    }

    func loadBrowser() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await api.fetchTree(root: selectedRoot, path: currentPath)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
            entries = []
        }
    }

    func loadPlaylists() async {
        do {
            playlists = try await api.fetchTree(root: .playlists)
                .filter(\.isDirectory)
                .map(\.name)
                .sorted()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func loadLibraryTracks() async {
        do {
            libraryTracks = try await api.fetchTree(root: .library)
                .filter { !$0.isDirectory }
                .sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }
        } catch {
            libraryTracks = []
        }
    }

    func select(_ track: Track) {
        selectedTrack = track
    }

    func play(_ track: Track) {
        selectedTrack = track
        player.play(track)
        selectedSection = .nowPlaying
    }

    func playEntry(_ entry: TreeEntry) {
        guard !entry.isDirectory else {
            return
        }
        play(entry.track(root: selectedRoot))
    }

    func download(url: String, playlist: String?, quality: Int) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Paste a YouTube or SoundCloud URL first."
            return
        }
        isLoading = true
        statusMessage = "Importing..."
        defer { isLoading = false }
        do {
            let track = try await api.download(url: trimmed, playlist: playlist?.isEmpty == false ? playlist : nil, quality: quality)
            selectedTrack = track
            player.play(track)
            statusMessage = "Imported \(track.displayTitle)."
            await reloadAll()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else {
            return
        }
        isLoading = true
        statusMessage = "Importing local audio..."
        defer { isLoading = false }

        var imported: [Track] = []
        var failures = 0
        for url in urls {
            do {
                let track = try await api.uploadAudio(fileURL: url, root: .library)
                imported.append(track)
            } catch {
                failures += 1
                statusMessage = error.localizedDescription
            }
        }

        if let last = imported.last {
            selectedTrack = last
        }
        if failures > 0 {
            statusMessage = "Imported \(imported.count), failed \(failures)."
        } else {
            statusMessage = "Imported \(imported.count) local \(imported.count == 1 ? "track" : "tracks")."
        }
        await reloadAll()
    }

    func createPlaylist(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Name the playlist first."
            return
        }
        do {
            let created = try await api.createPlaylist(name: trimmed)
            activePlaylist = created
            statusMessage = "Created \(created)."
            await loadPlaylists()
            await openPlaylist(created)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func openPlaylist(_ name: String) async {
        activePlaylist = name
        do {
            activePlaylistEntries = try await api.fetchTree(root: .playlists, path: name)
                .filter { !$0.isDirectory }
        } catch {
            statusMessage = error.localizedDescription
            activePlaylistEntries = []
        }
    }

    func addSelectedToActivePlaylist() async {
        guard let track = selectedTrack, let activePlaylist else {
            statusMessage = "Select a track and playlist first."
            return
        }
        await addToPlaylist(activePlaylist, track: track)
    }

    func addToPlaylist(_ playlist: String, track: Track) async {
        do {
            try await api.addToPlaylist(playlist, track: track)
            statusMessage = "Added to \(playlist)."
            if activePlaylist == playlist {
                await openPlaylist(playlist)
            }
            await loadPlaylists()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func playActivePlaylist() {
        let tracks = activePlaylistEntries
            .filter { !$0.isDirectory }
            .map { $0.track(root: .playlists) }
        guard let first = tracks.first else {
            statusMessage = "Select a playlist with tracks first."
            return
        }
        player.clearQueue()
        tracks.dropFirst().forEach { player.addToQueue($0) }
        play(first)
        statusMessage = "Queued \(tracks.count) \(tracks.count == 1 ? "track" : "tracks")."
    }

    func addActivePlaylistToQueue() {
        let tracks = activePlaylistEntries
            .filter { !$0.isDirectory }
            .map { $0.track(root: .playlists) }
        guard !tracks.isEmpty else {
            statusMessage = "Select a playlist with tracks first."
            return
        }
        tracks.forEach { player.addToQueue($0) }
        statusMessage = "Added \(tracks.count) to Up Next."
    }

    func applyPresetToActivePlaylist(_ preset: TunePreset) async {
        let tracks = activePlaylistEntries
            .filter { !$0.isDirectory }
            .map { $0.track(root: .playlists) }
        guard !tracks.isEmpty else {
            statusMessage = "Select a playlist with tracks first."
            return
        }

        isLoading = true
        statusMessage = "Rendering \(preset.id) for playlist..."
        defer { isLoading = false }

        var successCount = 0
        var failCount = 0
        for track in tracks {
            do {
                _ = try await api.tune(track: track, preset: preset)
                successCount += 1
            } catch {
                failCount += 1
            }
        }
        statusMessage = failCount > 0
            ? "Rendered \(successCount), skipped \(failCount)."
            : "Rendered \(successCount) playlist \(successCount == 1 ? "track" : "tracks")."
        selectedRoot = .edited
        await reloadAll()
    }

    func applyPreset(_ preset: TunePreset) async {
        guard let track = selectedTrack else {
            statusMessage = "Select a track before tuning."
            return
        }
        isLoading = true
        statusMessage = "Rendering \(preset.id)..."
        defer { isLoading = false }
        do {
            let tuned = try await api.tune(track: track, preset: preset)
            selectedTrack = tuned
            player.play(tuned)
            selectedRoot = .edited
            currentPath = ""
            statusMessage = "Rendered \(preset.id) to Rendered Tracks."
            await reloadAll()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func applyCut(start: Double, end: Double) async {
        guard let track = selectedTrack else {
            statusMessage = "Select a track before trimming."
            return
        }
        guard end > start else {
            statusMessage = "Cut end must be after cut start."
            return
        }

        isLoading = true
        statusMessage = "Rendering cut..."
        defer { isLoading = false }
        do {
            let edited = try await api.applyCuts(track: track, cuts: [CutRange(start: start, end: end)])
            selectedTrack = edited
            player.play(edited)
            selectedRoot = .edited
            currentPath = ""
            statusMessage = "Cut saved to Rendered Tracks."
            await reloadAll()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func rename(track: Track, newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Name cannot be empty."
            return
        }
        do {
            let renamed = try await api.rename(track: track, newName: trimmed)
            if selectedTrack?.id == track.id {
                selectedTrack = renamed
            }
            if player.currentTrack?.id == track.id {
                player.play(renamed)
            }
            statusMessage = "Renamed to \(renamed.fileName)."
            await reloadAll()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveToLibrary(track: Track) async {
        do {
            let saved = try await api.saveToLibrary(track: track)
            if selectedTrack?.id == track.id {
                selectedTrack = saved
            }
            if player.currentTrack?.id == track.id {
                player.play(saved)
            }
            statusMessage = "Saved to Local Library."
            await reloadAll()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func delete(track: Track) async {
        do {
            try await api.delete(track: track)
            if selectedTrack?.id == track.id {
                selectedTrack = nil
            }
            if player.currentTrack?.id == track.id {
                player.stop()
            }
            statusMessage = "Deleted \(track.fileName)."
            await reloadAll()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func openFolder(root: RootName, path: String?) async {
        do {
            try await api.openFolder(root: root, path: path)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func startParty() async {
        do {
            let code = try await api.startParty().uppercased()
            partyCode = code
            partyActive = true
            partyQueue = []
            statusMessage = "Party \(code) started."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func stopParty() async {
        do {
            try await api.stopParty()
            partyActive = false
            partyCode = nil
            partyQueue = []
            statusMessage = "Party stopped."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshPartyQueue() async {
        guard let partyCode else {
            return
        }
        do {
            partyQueue = try await api.partyQueue(code: partyCode)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func enqueuePartyURL(_ url: String, quality: Int) async {
        guard let partyCode else {
            statusMessage = "Start a party first."
            return
        }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Paste a YouTube or SoundCloud URL first."
            return
        }

        isLoading = true
        statusMessage = "Importing party track..."
        defer { isLoading = false }
        do {
            let item = try await api.partyEnqueue(code: partyCode, url: trimmed, quality: quality)
            partyQueue.append(item)
            player.addToQueue(item.track)
            statusMessage = "Added \(item.track.displayTitle) to Up Next."
            await reloadAll()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func openDataFolder() {
        guard let dataRootURL else {
            return
        }
        NSWorkspace.shared.open(dataRootURL)
    }
}
