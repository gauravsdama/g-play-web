import Foundation

struct GPlayAPI {
    let baseURL: URL

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func fetchTree(root: RootName, path: String = "") async throws -> [TreeEntry] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/tree"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "root", value: root.rawValue),
            URLQueryItem(name: "path", value: path),
        ]
        let response: TreeResponse = try await get(components.url!)
        return response.entries
    }

    func download(url: String, playlist: String?, quality: Int) async throws -> Track {
        let request = DownloadRequest(url: url, playlist: playlist, qualityKbps: quality)
        let response: TrackResponse = try await post("api/download", body: request)
        return response.track(defaultRoot: .library)
    }

    func createPlaylist(name: String) async throws -> String {
        let response: PlaylistResponse = try await post("api/playlists", body: PlaylistCreateRequest(name: name))
        return response.name
    }

    func addToPlaylist(_ playlist: String, track: Track) async throws {
        let request = PlaylistAddRequest(playlist: playlist, root: track.root.rawValue, path: track.path)
        let _: EmptyObject = try await post("api/playlists/add", body: request)
    }

    func tune(track: Track, preset: TunePreset) async throws -> Track {
        let request = TuneRequest(
            root: track.root.rawValue,
            path: track.path,
            preampDB: preset.preamp,
            eqGains: preset.eq,
            spatialWidth: preset.spatial / 100,
            drcMode: preset.drc,
            balance: 0,
            limiterOn: true,
            presetName: preset.id
        )
        let response: TrackResponse = try await post("api/tune", body: request)
        return response.track(defaultRoot: .edited)
    }

    func fileURL(for track: Track) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/file"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "root", value: track.root.rawValue),
            URLQueryItem(name: "path", value: track.path),
        ]
        return components.url!
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            if let error = try? decoder.decode(APIErrorResponse.self, from: data) {
                throw APIError.server(error.detail)
            }
            throw APIError.server("Request failed with status \(http.statusCode).")
        }
    }
}

enum APIError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        }
    }
}

private struct APIErrorResponse: Decodable {
    let detail: String
}

private struct TreeResponse: Decodable {
    let entries: [TreeEntry]
}

private struct EmptyObject: Decodable {}

private struct PlaylistResponse: Decodable {
    let name: String
}

private struct PlaylistCreateRequest: Encodable {
    let name: String
}

private struct PlaylistAddRequest: Encodable {
    let playlist: String
    let root: String
    let path: String
}

private struct DownloadRequest: Encodable {
    let url: String
    let playlist: String?
    let qualityKbps: Int

    enum CodingKeys: String, CodingKey {
        case url
        case playlist
        case qualityKbps = "quality_kbps"
    }
}

private struct TuneRequest: Encodable {
    let root: String
    let path: String
    let preampDB: Double
    let eqGains: [Double]
    let spatialWidth: Double
    let drcMode: String
    let balance: Double
    let limiterOn: Bool
    let presetName: String

    enum CodingKeys: String, CodingKey {
        case root
        case path
        case preampDB = "preamp_db"
        case eqGains = "eq_gains"
        case spatialWidth = "spatial_width"
        case drcMode = "drc_mode"
        case balance
        case limiterOn = "limiter_on"
        case presetName = "preset_name"
    }
}

private struct TrackResponse: Decodable {
    let root: RootName?
    let path: String
    let title: String?
    let artist: String?
    let thumbnail: String?
    let source: String?

    func track(defaultRoot: RootName) -> Track {
        Track(
            root: root ?? defaultRoot,
            path: path,
            title: title,
            artist: artist,
            thumbnail: thumbnail,
            source: source
        )
    }
}
