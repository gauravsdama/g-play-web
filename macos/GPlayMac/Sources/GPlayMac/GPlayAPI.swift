import Foundation

struct GPlayAPI {
    let baseURL: URL
    let apiToken: String

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let tokenHeader = "X-vantabeat-Token"

    func fetchTree(root: RootName, path: String = "") async throws -> [TreeEntry] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/tree"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "root", value: root.rawValue),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "token", value: apiToken),
        ]
        let response: TreeResponse = try await get(components.url!)
        return response.entries
    }

    func download(url: String, playlist: String?, quality: Int) async throws -> Track {
        let request = DownloadRequest(url: url, playlist: playlist, qualityKbps: quality)
        let response: TrackResponse = try await post("api/download", body: request)
        return response.track(defaultRoot: .library)
    }

    func uploadAudio(fileURL: URL, root: RootName = .library) async throws -> Track {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/upload"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "root", value: root.rawValue),
            URLQueryItem(name: "token", value: apiToken),
        ]

        let boundary = "vantabeat-\(UUID().uuidString)"
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(apiToken, forHTTPHeaderField: tokenHeader)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        var body = Data()
        let filename = fileURL.lastPathComponent
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.appendString("Content-Type: \(mimeTypeForAudio(fileURL))\r\n\r\n")
        body.append(try Data(contentsOf: fileURL))
        body.appendString("\r\n--\(boundary)--\r\n")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        try validate(data: data, response: response)
        let trackResponse = try decoder.decode(TrackResponse.self, from: data)
        return trackResponse.track(defaultRoot: root)
    }

    func createPlaylist(name: String) async throws -> String {
        let response: PlaylistResponse = try await post("api/playlists", body: PlaylistCreateRequest(name: name))
        return response.name
    }

    func addToPlaylist(_ playlist: String, track: Track) async throws {
        let request = PlaylistAddRequest(playlist: playlist, root: track.root.rawValue, path: track.path)
        let _: EmptyObject = try await post("api/playlists/add", body: request)
    }

    func rename(track: Track, newName: String) async throws -> Track {
        let request = RenameRequest(root: track.root.rawValue, path: track.path, newName: newName)
        let response: TrackResponse = try await post("api/rename", body: request)
        return response.track(defaultRoot: track.root)
    }

    func saveToLibrary(track: Track) async throws -> Track {
        let request = TrackPathRequest(root: track.root.rawValue, path: track.path)
        let response: TrackResponse = try await post("api/save-to-library", body: request)
        return response.track(defaultRoot: .library)
    }

    func delete(track: Track) async throws {
        let request = TrackPathRequest(root: track.root.rawValue, path: track.path)
        let _: EmptyObject = try await post("api/delete", body: request)
    }

    func openFolder(root: RootName, path: String?) async throws {
        let request = OpenFolderRequest(root: root.rawValue, path: path)
        let _: EmptyObject = try await post("api/open-folder", body: request)
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

    func applyCuts(track: Track, cuts: [CutRange]) async throws -> Track {
        let request = EditCutsRequest(root: track.root.rawValue, path: track.path, cuts: cuts)
        let response: TrackResponse = try await post("api/edit-cuts", body: request)
        return response.track(defaultRoot: .edited)
    }

    func startParty() async throws -> String {
        let response: PartyStartResponse = try await post("api/party/start", body: EmptyRequest())
        return response.code
    }

    func stopParty() async throws {
        let _: EmptyObject = try await post("api/party/stop", body: EmptyRequest())
    }

    func partyQueue(code: String) async throws -> [PartyItem] {
        let response: PartyQueueResponse = try await post("api/party/queue", body: PartyQueueRequest(code: code))
        return response.queue.map(\.partyItem)
    }

    func partyEnqueue(code: String, url: String, quality: Int) async throws -> PartyItem {
        let response: PartyItemResponse = try await post(
            "api/party/enqueue",
            body: PartyEnqueueRequest(code: code, url: url, qualityKbps: quality)
        )
        return response.partyItem
    }

    func fileURL(for track: Track) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/file"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "root", value: track.root.rawValue),
            URLQueryItem(name: "path", value: track.path),
            URLQueryItem(name: "token", value: apiToken),
        ]
        return components.url!
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(apiToken, forHTTPHeaderField: tokenHeader)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiToken, forHTTPHeaderField: tokenHeader)
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func mimeTypeForAudio(_ fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "aac": return "audio/aac"
        case "aif", "aiff": return "audio/aiff"
        case "flac": return "audio/flac"
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        default: return "application/octet-stream"
        }
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

private struct EmptyRequest: Encodable {}

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

private struct TrackPathRequest: Encodable {
    let root: String
    let path: String
}

private struct RenameRequest: Encodable {
    let root: String
    let path: String
    let newName: String

    enum CodingKeys: String, CodingKey {
        case root
        case path
        case newName = "new_name"
    }
}

private struct OpenFolderRequest: Encodable {
    let root: String
    let path: String?
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

private struct EditCutsRequest: Encodable {
    let root: String
    let path: String
    let cuts: [CutRange]
}

private struct PartyStartResponse: Decodable {
    let code: String
}

private struct PartyQueueRequest: Encodable {
    let code: String
}

private struct PartyEnqueueRequest: Encodable {
    let code: String
    let url: String
    let qualityKbps: Int

    enum CodingKeys: String, CodingKey {
        case code
        case url
        case qualityKbps = "quality_kbps"
    }
}

private struct PartyQueueResponse: Decodable {
    let queue: [PartyItemResponse]
}

private struct PartyItemResponse: Decodable {
    let id: String
    let track: TrackResponse

    var partyItem: PartyItem {
        PartyItem(id: id, track: track.track(defaultRoot: .library))
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

private extension Data {
    mutating func appendString(_ value: String) {
        append(Data(value.utf8))
    }
}
