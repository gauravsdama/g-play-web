import SwiftUI

struct NativeAppView: View {
    @StateObject private var store: GPlayStore

    init(baseURL: URL, apiToken: String, dataRootURL: URL?) {
        _store = StateObject(wrappedValue: GPlayStore(baseURL: baseURL, apiToken: apiToken, dataRootURL: dataRootURL))
    }

    var body: some View {
        NavigationSplitView {
            AppSidebar(store: store)
                .navigationSplitViewColumnWidth(min: 248, ideal: 292, max: 340)
        } detail: {
            MainSurface(store: store)
        }
        .task {
            await store.start()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBar(player: store.player, selectedTrack: store.selectedTrack) {
                if let track = store.selectedTrack {
                    store.play(track)
                }
            } openNowPlaying: {
                store.selectedSection = .nowPlaying
            }
        }
    }
}

struct AppSidebar: View {
    @ObservedObject var store: GPlayStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.linearGradient(colors: [.gAccent, .gMint], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "music.note")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("vantabeat")
                        .font(.title3.weight(.semibold))
                    Text("Local music studio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 7) {
                Text("Browse")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(AppSection.allCases) { section in
                    Button {
                        store.selectedSection = section
                    } label: {
                        Label(section.title, systemImage: section.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(SidebarButtonStyle(isSelected: store.selectedSection == section))
                    .accessibilityAddTraits(store.selectedSection == section ? .isSelected : [])
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Sources")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(RootName.allCases) { root in
                    Button {
                        Task {
                            await store.changeRoot(root)
                            store.selectedSection = .library
                        }
                    } label: {
                        HStack {
                            Label(root.title, systemImage: root.symbol)
                            Spacer()
                            if store.selectedRoot == root {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SourceButtonStyle(isSelected: store.selectedRoot == root))
                }
            }

            Spacer()

            Button {
                store.openDataFolder()
            } label: {
                Label("Open Data Folder", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SourceButtonStyle(isSelected: false))
        }
        .padding(18)
        .background(Color.gBackground)
    }
}

struct MainSurface: View {
    @ObservedObject var store: GPlayStore

    var body: some View {
        ZStack {
            Color.gBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HeaderView(store: store)
                    StatusBanner(message: store.statusMessage)

                    switch store.selectedSection {
                    case .library:
                        LibraryView(store: store)
                    case .nowPlaying:
                        NowPlayingNativeView(store: store)
                    case .download:
                        DownloadNativeView(store: store)
                    case .playlists:
                        PlaylistsNativeView(store: store)
                    case .party:
                        PartyNativeView(store: store)
                    case .tuning:
                        TuningNativeView(store: store)
                    case .visualizer:
                        VisualizerNativeView(player: store.player)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 120)
                .frame(maxWidth: 1240, alignment: .leading)
            }
        }
    }
}

struct HeaderView: View {
    @ObservedObject var store: GPlayStore

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.selectedSection.title)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading")
            }

            Button {
                Task {
                    await store.reloadAll()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var subtitle: String {
        switch store.selectedSection {
        case .library:
            return "\(store.selectedRoot.title) · \(store.currentPath.isEmpty ? "Root" : store.currentPath)"
        case .nowPlaying:
            return store.player.currentTrack?.displayTitle ?? "Select a track from Library"
        case .download:
            return "Import audio into your local library"
        case .playlists:
            return "Organize local tracks without syncing them anywhere"
        case .party:
            return "Build a shared Up Next queue on this Mac"
        case .tuning:
            return "Render EQ presets into versioned local tracks"
        case .visualizer:
            return "Native reactive playback canvas"
        }
    }
}

struct SidebarButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.gAccent : Color.clear)
                    .opacity(configuration.isPressed ? 0.78 : 1)
            )
    }
}

struct SourceButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(.primary)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.gSurfaceRaised : Color.gSurface.opacity(configuration.isPressed ? 0.9 : 0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.gAccent.opacity(0.65) : .white.opacity(0.07), lineWidth: 1)
            )
    }
}
