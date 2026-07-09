import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case library
    case nowPlaying
    case visualizer
    case tuning
    case playlists
    case party
    case download

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .nowPlaying: return "Now Playing"
        case .download: return "Imports"
        case .playlists: return "Playlists"
        case .party: return "Party"
        case .tuning: return "EQ"
        case .visualizer: return "Visualiser"
        }
    }

    var symbol: String {
        switch self {
        case .library: return "music.note.list"
        case .nowPlaying: return "play.circle"
        case .download: return "arrow.down.circle"
        case .playlists: return "rectangle.stack"
        case .party: return "person.2.wave.2"
        case .tuning: return "slider.horizontal.3"
        case .visualizer: return "waveform.path.ecg"
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Recent"
        case .name: return "Name"
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
        case .library: return "Local Library"
        case .edited: return "Rendered Tracks"
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
        if source == "youtube" {
            return "YouTube"
        }
        if source == "soundcloud" {
            return "SoundCloud"
        }
        if source == "local" {
            return "Local file"
        }
        return root.title
    }
}

struct CutRange: Codable, Hashable, Identifiable {
    let start: Double
    let end: Double

    var id: String { "\(start)-\(end)" }
}

struct PartyItem: Hashable, Identifiable {
    let id: String
    let track: Track
}

struct TunePreset: Identifiable, Hashable {
    let id: String
    let preamp: Double
    let eq: [Double]
    let spatial: Double
    let drc: String

    static let all: [TunePreset] = [
        TunePreset(id: "Flat", preamp: 0, eq: Array(repeating: 0, count: 10), spatial: 0, drc: "Off"),
        TunePreset(id: "High-End Spatial Audio", preamp: 0, eq: [3, 3, 2, -1, -1, 0, 1, 2, 3, 3], spatial: 45, drc: "Off"),
        TunePreset(id: "Late Night", preamp: -2, eq: [1, 1.5, 1, 0, -0.5, -1, -1, -0.5, 0, 0.5], spatial: 12, drc: "Soft"),
        TunePreset(id: "Acoustic", preamp: 0, eq: [2, 2, 1, 0, 0, 1, 2, 2, 2, 1], spatial: 0, drc: "Off"),
        TunePreset(id: "Bass Booster", preamp: 0, eq: [5, 4, 3, 2, 1, 0, -1, -2, -2, -2], spatial: 0, drc: "Off"),
        TunePreset(id: "Bass Reducer", preamp: 0, eq: [-4, -4, -3, -2, -1, 0, 0, 0, 0, 0], spatial: 0, drc: "Off"),
        TunePreset(id: "Classical", preamp: 0, eq: [3, 2, 1, -1, -2, -1, 1, 2, 3, 3], spatial: 10, drc: "Off"),
        TunePreset(id: "Club", preamp: -1, eq: [3, 2.5, 1, 0, -0.5, 0, 1, 2, 2.5, 2], spatial: 18, drc: "Medium"),
        TunePreset(id: "Dance", preamp: 0, eq: [5, 4, 3, 1, 0, 1, 2, 3, 3, 2], spatial: 10, drc: "Off"),
        TunePreset(id: "Deep", preamp: 0, eq: [3, 2, 2, 1, 0, 0, -1, -2, -2, -3], spatial: 0, drc: "Off"),
        TunePreset(id: "Electronic", preamp: 0, eq: [5, 4, 3, 0, -2, -2, -1, 0, 1, 2], spatial: 10, drc: "Off"),
        TunePreset(id: "Hip-Hop", preamp: 0, eq: [4, 4, 3, 2, 1, 0, -1, 0, 2, 2], spatial: 0, drc: "Off"),
        TunePreset(id: "Jazz", preamp: 0, eq: [3, 2, 1, -1, -2, -1, 1, 2, 2, 3], spatial: 10, drc: "Off"),
        TunePreset(id: "Latin", preamp: 0, eq: [4, 3, 2, -1, -2, -1, 1, 2, 3, 4], spatial: 10, drc: "Off"),
        TunePreset(id: "Loudness", preamp: 0, eq: [4, 3, 2, -1, -2, -2, -1, 0, 2, 2], spatial: 0, drc: "Off"),
        TunePreset(id: "Lounge", preamp: 0, eq: [-2, -2, -1, 1, 2, 2, 1, 0, -1, -2], spatial: 0, drc: "Off"),
        TunePreset(id: "Piano", preamp: 0, eq: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1], spatial: 0, drc: "Off"),
        TunePreset(id: "Pop", preamp: 0, eq: [-1, -1, 0, 1, 2, 2, 1, 0, -1, -1], spatial: 0, drc: "Off"),
        TunePreset(id: "R&B", preamp: 0, eq: [5, 4, 3, 0, -2, -2, -1, 0, 1, 2], spatial: 0, drc: "Off"),
        TunePreset(id: "Rock", preamp: 0, eq: [4, 3, 2, 0, -1, -1, 0, 2, 3, 3], spatial: 0, drc: "Off"),
        TunePreset(id: "Small Speakers", preamp: 0, eq: [3, 3, 2, 1, 0, -1, -2, -3, -3, -3], spatial: 0, drc: "Off"),
        TunePreset(id: "Spoken Word", preamp: 0, eq: [-4, -3, -2, 1, 3, 3, 2, 1, 0, 0], spatial: 0, drc: "Off"),
        TunePreset(id: "Treble Booster", preamp: 0, eq: [0, 0, 0, 0, 0, 1, 2, 3, 4, 4], spatial: 0, drc: "Off"),
        TunePreset(id: "Treble Reducer", preamp: 0, eq: [0, 0, 0, 0, 0, -1, -2, -3, -4, -4], spatial: 0, drc: "Off"),
        TunePreset(id: "Vocal Booster", preamp: 0, eq: [-1, -1, 0, 2, 3, 3, 2, 1, 0, -1], spatial: 0, drc: "Off"),
        TunePreset(id: "Vocal Focus", preamp: 0, eq: [-1, -1, 0, 1.5, 2.5, 2, 1, 0, -0.5, -1], spatial: 6, drc: "Soft"),
        TunePreset(id: "Warm", preamp: -1, eq: [2, 1.5, 1, 0.5, 0, -0.5, -0.5, 0, 0.5, 1], spatial: 8, drc: "Off"),
    ]
}

let eqBands = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

func cleanTitle(_ value: String) -> String {
    value
        .replacingOccurrences(of: "_gplay_tuned", with: "")
        .replacingOccurrences(of: "_vantabeat_tuned", with: "")
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
