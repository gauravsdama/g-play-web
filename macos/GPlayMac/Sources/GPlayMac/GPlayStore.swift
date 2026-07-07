import AppKit
import Foundation

@MainActor
final class GPlayStore: ObservableObject {
    let api: GPlayAPI
    let player: PlayerController
    let dataRootURL: URL?

    @Published var selectedSection: AppSection = .library
    @Published var selectedRoot: RootName = .library
    @Published var currentPath = ""
    @Published var entries: [TreeEntry] = []
    @Published var selectedTrack: Track?
    @Published var playlists: [String] = []
    @Published var activePlaylist: String?
    @Published var activePlaylistEntries: [TreeEntry] = []
    @Published var libraryTracks: [TreeEntry] = []
    @Published var statusMessage: String?
    @Published var isLoading = false

    init(baseURL: URL, dataRootURL: URL?) {
        self.api = GPlayAPI(baseURL: baseURL)
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
            statusMessage = "Paste a YouTube URL first."
            return
        }
        isLoading = true
        statusMessage = "Downloading..."
        defer { isLoading = false }
        do {
            let track = try await api.download(url: trimmed, playlist: playlist?.isEmpty == false ? playlist : nil, quality: quality)
            selectedTrack = track
            player.play(track)
            statusMessage = "Downloaded \(track.displayTitle)."
            await reloadAll()
        } catch {
            statusMessage = error.localizedDescription
        }
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
        do {
            try await api.addToPlaylist(activePlaylist, track: track)
            statusMessage = "Added to \(activePlaylist)."
            await openPlaylist(activePlaylist)
        } catch {
            statusMessage = error.localizedDescription
        }
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
            statusMessage = "Rendered \(preset.id) to Edited."
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
