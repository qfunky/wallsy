import Foundation
import CryptoKit

struct ServerConfig: Equatable {
    var baseURL: URL
    var username: String
    var password: String
}

enum SubsonicError: LocalizedError {
    case http(Int)
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .http(let code):
            return "Server returned HTTP \(code)."
        case .server(let message):
            return message
        case .invalidResponse:
            return "Unexpected response from server."
        }
    }
}

enum AlbumListType: String {
    case newest
    case recent
    case frequent
    case random
    case starred
    case alphabeticalByName
}

final class SubsonicClient {
    let config: ServerConfig
    /// Session that honors system proxy settings (e.g. an HTTP proxy into a VPN/tailnet).
    private let session: URLSession
    /// Session that always connects directly, bypassing any system proxy.
    private let directSession: URLSession
    private let decoder = JSONDecoder()

    init(config: ServerConfig) {
        self.config = config

        let cache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024
        )

        let proxied = URLSessionConfiguration.default
        proxied.urlCache = cache
        proxied.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: proxied)

        let direct = URLSessionConfiguration.default
        direct.urlCache = cache
        direct.timeoutIntervalForRequest = 10
        direct.connectionProxyDictionary = [:] // force direct connection
        self.directSession = URLSession(configuration: direct)
    }

    // MARK: - URL building

    func url(for endpoint: String, params: [String: String] = [:]) -> URL {
        url(for: endpoint, items: params.map { URLQueryItem(name: $0.key, value: $0.value) })
    }

    /// Variant that supports repeated query parameters (e.g. multiple `songId`).
    func url(for endpoint: String, items extraItems: [URLQueryItem]) -> URL {
        let base = config.baseURL.appendingPathComponent("rest").appendingPathComponent(endpoint)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!

        let salt = Self.randomSalt(length: 16)
        let token = Insecure.MD5
            .hash(data: Data((config.password + salt).utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        var items = [
            URLQueryItem(name: "u", value: config.username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: "1.16.1"),
            URLQueryItem(name: "c", value: "Wallsy"),
            URLQueryItem(name: "f", value: "json"),
        ]
        items.append(contentsOf: extraItems)
        components.queryItems = items
        return components.url!
    }

    func streamURL(id: String) -> URL {
        url(for: "stream", params: ["id": id])
    }

    func coverArtURL(id: String, size: Int) -> URL {
        url(for: "getCoverArt", params: ["id": id, "size": String(size)])
    }

    private static func randomSalt(length: Int) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }

    // MARK: - Generic request

    /// Fetches data trying the system-proxy path first, then falls back to a
    /// direct connection. This makes the client resilient to a configured-but-dead
    /// system proxy (e.g. VPN/tailscale proxy stopped while on the home LAN).
    private func fetch(_ requestURL: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: requestURL)
        } catch let error as URLError {
            switch error.code {
            case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .timedOut:
                return try await directSession.data(from: requestURL)
            default:
                throw error
            }
        }
    }

    private func request<T: Decodable>(_ endpoint: String,
                                       params: [String: String] = [:],
                                       as type: T.Type) async throws -> T {
        try await request(endpoint, items: params.map { URLQueryItem(name: $0.key, value: $0.value) }, as: type)
    }

    private func request<T: Decodable>(_ endpoint: String,
                                       items: [URLQueryItem],
                                       as type: T.Type) async throws -> T {
        let (data, response) = try await fetch(url(for: endpoint, items: items))
        guard let http = response as? HTTPURLResponse else {
            throw SubsonicError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SubsonicError.http(http.statusCode)
        }

        let envelope = try decoder.decode(SubsonicResponse<StatusEnvelope>.self, from: data)
        guard envelope.subsonicResponse.status == "ok" else {
            let message = envelope.subsonicResponse.error?.message ?? "Unknown server error"
            throw SubsonicError.server(message)
        }

        return try decoder.decode(SubsonicResponse<T>.self, from: data).subsonicResponse
    }

    // MARK: - Endpoints

    func ping() async throws {
        _ = try await request("ping", as: StatusEnvelope.self)
    }

    func albumList(type: AlbumListType, size: Int = 30, offset: Int = 0) async throws -> [Album] {
        let payload = try await request(
            "getAlbumList2",
            params: ["type": type.rawValue, "size": String(size), "offset": String(offset)],
            as: AlbumList2Payload.self
        )
        return payload.albumList2.album ?? []
    }

    /// Fetches the full album list page by page.
    func allAlbums(pageSize: Int = 200, maxAlbums: Int = 5000) async throws -> [Album] {
        var result: [Album] = []
        var offset = 0
        while offset < maxAlbums {
            let page = try await albumList(type: .alphabeticalByName, size: pageSize, offset: offset)
            result.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }
        return result
    }

    func album(id: String) async throws -> Album {
        try await request("getAlbum", params: ["id": id], as: AlbumPayload.self).album
    }

    func artists() async throws -> [ArtistIndex] {
        try await request("getArtists", as: ArtistsPayload.self).artists.index ?? []
    }

    func artist(id: String) async throws -> Artist {
        try await request("getArtist", params: ["id": id], as: ArtistPayload.self).artist
    }

    func playlists() async throws -> [Playlist] {
        try await request("getPlaylists", as: PlaylistsPayload.self).playlists.playlist ?? []
    }

    func playlist(id: String) async throws -> Playlist {
        try await request("getPlaylist", params: ["id": id], as: PlaylistPayload.self).playlist
    }

    // MARK: - Playlist management

    func createPlaylist(name: String, songIds: [String]) async throws {
        var items = [URLQueryItem(name: "name", value: name)]
        items.append(contentsOf: songIds.map { URLQueryItem(name: "songId", value: $0) })
        _ = try await request("createPlaylist", items: items, as: StatusEnvelope.self)
    }

    func addToPlaylist(id: String, songIds: [String]) async throws {
        var items = [URLQueryItem(name: "playlistId", value: id)]
        items.append(contentsOf: songIds.map { URLQueryItem(name: "songIdToAdd", value: $0) })
        _ = try await request("updatePlaylist", items: items, as: StatusEnvelope.self)
    }

    /// Removes songs by their positions (0-based) within the playlist.
    func removeFromPlaylist(id: String, indices: [Int]) async throws {
        var items = [URLQueryItem(name: "playlistId", value: id)]
        items.append(contentsOf: indices.map { URLQueryItem(name: "songIndexToRemove", value: String($0)) })
        _ = try await request("updatePlaylist", items: items, as: StatusEnvelope.self)
    }

    /// Replaces a playlist's entire contents (used for drag-reordering).
    func replacePlaylist(id: String, songIds: [String]) async throws {
        var items = [URLQueryItem(name: "playlistId", value: id)]
        items.append(contentsOf: songIds.map { URLQueryItem(name: "songId", value: $0) })
        _ = try await request("createPlaylist", items: items, as: StatusEnvelope.self)
    }

    func deletePlaylist(id: String) async throws {
        _ = try await request("deletePlaylist", params: ["id": id], as: StatusEnvelope.self)
    }

    /// Pages through the entire song library. Navidrome supports an empty
    /// `search3` query as "list everything" (OpenSubsonic extension).
    func allSongs(pageSize: Int = 500, maxSongs: Int = 10000) async throws -> [Song] {
        var result: [Song] = []
        var offset = 0
        while offset < maxSongs {
            let page = try await request(
                "search3",
                params: [
                    "query": "",
                    "songCount": String(pageSize),
                    "songOffset": String(offset),
                    "albumCount": "0",
                    "artistCount": "0",
                ],
                as: Search3Payload.self
            ).searchResult3.song ?? []
            result.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }
        return result
    }

    func search(_ query: String) async throws -> SearchResult3 {
        try await request(
            "search3",
            params: [
                "query": query,
                "songCount": "25",
                "albumCount": "12",
                "artistCount": "8",
            ],
            as: Search3Payload.self
        ).searchResult3
    }

    func randomSongs(size: Int = 50) async throws -> [Song] {
        try await request(
            "getRandomSongs",
            params: ["size": String(size)],
            as: RandomSongsPayload.self
        ).randomSongs.song ?? []
    }

    func starredSongs() async throws -> [Song] {
        try await request("getStarred2", as: Starred2Payload.self).starred2.song ?? []
    }

    func setStar(id: String, starred: Bool) async throws {
        _ = try await request(starred ? "star" : "unstar", params: ["id": id], as: StatusEnvelope.self)
    }

    /// Fire-and-forget scrobble. `submission: false` = "now playing", `true` = play count.
    func scrobble(id: String, submission: Bool) {
        Task {
            _ = try? await request(
                "scrobble",
                params: ["id": id, "submission": submission ? "true" : "false"],
                as: StatusEnvelope.self
            )
        }
    }
}
