import SwiftUI

struct LibraryView: View {
    @ObservedObject var store: GPlayStore

    private var sortedEntries: [TreeEntry] {
        store.entries.sorted { left, right in
            if left.isDirectory != right.isDirectory {
                return left.isDirectory
            }
            if left.isDirectory {
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
            switch store.librarySort {
            case .recent:
                return (left.addedAt ?? 0) > (right.addedAt ?? 0)
            case .name:
                break
            }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RootPicker(store: store)
            Breadcrumbs(store: store)

            AppCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(store.selectedRoot.title, systemImage: store.selectedRoot.symbol)
                            .font(.headline)
                        Spacer()
                        Picker("Sort", selection: $store.librarySort) {
                            ForEach(LibrarySort.allCases) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                        .frame(width: 150)
                        Text("\(sortedEntries.count) items")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if sortedEntries.isEmpty {
                        EmptyStateView(
                            title: "No tracks here",
                            systemImage: "music.note",
                            description: "Use Download or add files to the data folder."
                        )
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(sortedEntries) { entry in
                                LibraryRow(
                                    entry: entry,
                                    root: store.selectedRoot,
                                    open: {
                                        if entry.isDirectory {
                                            Task { await store.openPath(entry.path) }
                                        } else {
                                            store.select(entry.track(root: store.selectedRoot))
                                        }
                                    },
                                    play: {
                                        store.playEntry(entry)
                                    },
                                    queue: {
                                        store.player.addToQueue(entry.track(root: store.selectedRoot))
                                    },
                                    openInFinder: {
                                        Task { await store.openFolder(root: store.selectedRoot, path: entry.path) }
                                    },
                                    saveToLibrary: entry.isDirectory || store.selectedRoot != .edited ? nil : {
                                        let task = Task { await store.saveToLibrary(track: entry.track(root: store.selectedRoot)) }
                                        _ = task
                                    },
                                    delete: entry.isDirectory || (store.selectedRoot != .library && store.selectedRoot != .edited) ? nil : {
                                        let task = Task { await store.delete(track: entry.track(root: store.selectedRoot)) }
                                        _ = task
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

struct RootPicker: View {
    @ObservedObject var store: GPlayStore

    var body: some View {
        HStack(spacing: 8) {
            ForEach(RootName.allCases) { root in
                Button {
                    Task { await store.changeRoot(root) }
                } label: {
                    Label(root.title, systemImage: root.symbol)
                        .frame(minWidth: 108)
                }
                .buttonStyle(.borderedProminent)
                .tint(store.selectedRoot == root ? .gAccent : .gSurfaceRaised)
                .accessibilityAddTraits(store.selectedRoot == root ? .isSelected : [])
            }
        }
    }
}

struct Breadcrumbs: View {
    @ObservedObject var store: GPlayStore

    var body: some View {
        HStack(spacing: 6) {
            Button(store.selectedRoot.title) {
                Task { await store.openPath("") }
            }
            .buttonStyle(.borderless)

            ForEach(pathCrumbs, id: \.path) { crumb in
                Text("/")
                    .foregroundStyle(.tertiary)
                Button(crumb.label) {
                    Task { await store.openPath(crumb.path) }
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var pathParts: [String] {
        store.currentPath.isEmpty ? [] : store.currentPath.split(separator: "/").map(String.init)
    }

    private var pathCrumbs: [(label: String, path: String)] {
        var cursor = ""
        return pathParts.map { part in
            cursor = cursor.isEmpty ? part : "\(cursor)/\(part)"
            return (part, cursor)
        }
    }
}

struct LibraryRow: View {
    let entry: TreeEntry
    let root: RootName
    let open: () -> Void
    let play: () -> Void
    let queue: () -> Void
    let openInFinder: (() -> Void)?
    let saveToLibrary: (() -> Void)?
    let delete: (() -> Void)?

    init(
        entry: TreeEntry,
        root: RootName,
        open: @escaping () -> Void,
        play: @escaping () -> Void,
        queue: @escaping () -> Void,
        openInFinder: (() -> Void)? = nil,
        saveToLibrary: (() -> Void)? = nil,
        delete: (() -> Void)? = nil
    ) {
        self.entry = entry
        self.root = root
        self.open = open
        self.play = play
        self.queue = queue
        self.openInFinder = openInFinder
        self.saveToLibrary = saveToLibrary
        self.delete = delete
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 13) {
                    if entry.isDirectory {
                        FolderTile()
                    } else {
                        ArtworkView(track: entry.track(root: root), size: 48)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.isDirectory ? entry.name : cleanTitle(entry.title ?? entry.name))
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        Text(entry.isDirectory ? "Folder" : entry.artist ?? "Unknown artist")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if !entry.isDirectory {
                        Text(sourceLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    if entry.isDirectory {
                        open()
                    } else {
                        play()
                    }
                }
            )

            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 10)
                    .accessibilityHidden(true)
            } else {
                Button(action: play) {
                    Image(systemName: "play.fill")
                        .font(.callout.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .contentShape(Circle())
                .padding(.trailing, 8)
                .accessibilityLabel("Play \(entry.title ?? entry.name)")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.gSurface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .contextMenu {
            if entry.isDirectory {
                Button("Open Folder", action: open)
                if let openInFinder {
                    Button("Show in Finder", action: openInFinder)
                }
            } else {
                Button("Play", action: play)
                Button("Play Next") {
                    queue()
                }
                if let openInFinder {
                    Button("Show in Finder", action: openInFinder)
                }
                if let saveToLibrary {
                    Button("Save to Library", action: saveToLibrary)
                }
                if let delete {
                    Button("Delete", role: .destructive, action: delete)
                }
            }
        }
        .accessibilityLabel(entry.isDirectory ? "Folder \(entry.name)" : "Track \(entry.title ?? entry.name), \(entry.artist ?? "Unknown artist")")
    }

    private var sourceLabel: String {
        switch entry.source {
        case "youtube":
            return "YouTube"
        case "soundcloud":
            return "SoundCloud"
        default:
            return root.title
        }
    }
}

struct FolderTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.thinMaterial)
            .overlay {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.gAccent)
            }
            .frame(width: 48, height: 48)
            .accessibilityHidden(true)
    }
}

struct LibraryRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? Color.gSurfaceRaised : Color.gSurface.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
    }
}
