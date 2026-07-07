import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case library
    case nowPlaying
    case download
    case playlists
    case tuning
    case visualizer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .nowPlaying: return "Now Playing"
        case .download: return "Download"
        case .playlists: return "Playlists"
        case .tuning: return "Tuning"
        case .visualizer: return "Visualizer"
        }
    }

    var symbol: String {
        switch self {
        case .library: return "music.note.list"
        case .nowPlaying: return "play.circle"
        case .download: return "arrow.down.circle"
        case .playlists: return "rectangle.stack"
        case .tuning: return "slider.horizontal.3"
        case .visualizer: return "waveform.path.ecg"
        }
    }
}

enum RootName: String, CaseIterable, Codable, Identifiable {
    case library = "Library"
    case edited = "Edited"
    case playlists = "Playlists"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .edited: return "Edited"
        case .playlists: return "Playlists"
        }
    }

    var symbol: String {
        switch self {
        case .library: return "music.note.house"
        case .edited: return "wand.and.stars"
        case .playlists: return "music.note.list"
        }
    }
}

enum TreeEntryKind: String, Codable {
    case dir
    case file
}

struct TreeEntry: Codable, Hashable, Identifiable {
    let name: String
    let type: TreeEntryKind
    let path: String
    let title: String?
    let artist: String?
    let thumbnail: String?
    let addedAt: Double?
    let source: String?

    var id: String { path }
    var isDirectory: Bool { type == .dir }

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case path
        case title
        case artist
        case thumbnail
        case addedAt = "added_at"
        case source
    }

    func track(root: RootName) -> Track {
        Track(
            root: root,
            path: path,
            title: title ?? name,
            artist: artist,
            thumbnail: thumbnail,
            source: source
        )
    }
}

struct Track: Codable, Hashable, Identifiable {
    let root: RootName
    let path: String
    let title: String?
    let artist: String?
    let thumbnail: String?
    let source: String?

    var id: String { "\(root.rawValue):\(path)" }

    var displayTitle: String {
        let fallback = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return cleanTitle(title ?? fallback)
    }

    var displayArtist: String {
        let value = artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : "Unknown artist"
    }

    var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var sourceLabel: String {
        if source == "youtube" || thumbnail != nil {
            return "YouTube"
        }
        if source == "local" {
            return "Local file"
        }
        return root.title
    }
}

struct TunePreset: Identifiable, Hashable {
    let id: String
    let preamp: Double
    let eq: [Double]
    let spatial: Double
    let drc: String

    static let all: [TunePreset] = [
        TunePreset(id: "Flat", preamp: 0, eq: Array(repeating: 0, count: 10), spatial: 0, drc: "Off"),
        TunePreset(id: "Late Night", preamp: -2, eq: [1, 1.5, 1, 0, -0.5, -1, -1, -0.5, 0, 0.5], spatial: 12, drc: "Soft"),
        TunePreset(id: "Club", preamp: -1, eq: [3, 2.5, 1, 0, -0.5, 0, 1, 2, 2.5, 2], spatial: 18, drc: "Medium"),
        TunePreset(id: "Vocal Focus", preamp: 0, eq: [-1, -1, 0, 1.5, 2.5, 2, 1, 0, -0.5, -1], spatial: 6, drc: "Soft"),
        TunePreset(id: "Warm", preamp: -1, eq: [2, 1.5, 1, 0.5, 0, -0.5, -0.5, 0, 0.5, 1], spatial: 8, drc: "Off"),
    ]
}

let eqBands = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

func cleanTitle(_ value: String) -> String {
    value
        .replacingOccurrences(of: "_gplay_tuned", with: "")
        .replacingOccurrences(of: "_", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func formattedDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else {
        return "0:00"
    }
    let whole = Int(seconds.rounded(.down))
    return "\(whole / 60):\(String(format: "%02d", whole % 60))"
}
