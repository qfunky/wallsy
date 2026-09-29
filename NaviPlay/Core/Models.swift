import Foundation

// MARK: - Domain models (Subsonic API v1.16.1, as served by Navidrome)

struct Song: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let album: String?
    let albumId: String?
    let artist: String?
    let artistId: String?
    let track: Int?
    let discNumber: Int?
    let year: Int?
    let genre: String?
    let coverArt: String?
    let duration: Int?
    let bitRate: Int?
    let suffix: String?
    let size: Int64?
    let path: String?
    let starred: String?
    let playCount: Int?
    let played: String?
}

struct Album: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let songCount: Int?
    let duration: Int?
    let year: Int?
    let genre: String?
    let starred: String?
    let playCount: Int?
    let song: [Song]?
}

struct Artist: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let coverArt: String?
    let albumCount: Int?
    let artistImageUrl: String?
    let starred: String?
    let album: [Album]?
}

struct ArtistIndex: Decodable, Hashable {
    let name: String
    let artist: [Artist]
}

struct Playlist: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let comment: String?
    let owner: String?
    let songCount: Int?
    let duration: Int?
    let coverArt: String?
    let entry: [Song]?
}

struct SearchResult3: Decodable {
    let artist: [Artist]?
    let album: [Album]?
    let song: [Song]?
}

// MARK: - Response envelopes

struct SubsonicResponse<T: Decodable>: Decodable {
    let subsonicResponse: T

    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

struct StatusEnvelope: Decodable {
    let status: String
    let error: APIError?
}

struct APIError: Decodable {
    let code: Int
    let message: String?
}

// MARK: - Per-endpoint payload wrappers

struct AlbumList2Payload: Decodable {
    let albumList2: AlbumList2

    struct AlbumList2: Decodable {
        let album: [Album]?
    }
}

struct AlbumPayload: Decodable {
    let album: Album
}

struct SongPayload: Decodable {
    let song: Song
}

struct ArtistsPayload: Decodable {
    let artists: Container

    struct Container: Decodable {
        let index: [ArtistIndex]?
    }
}

struct ArtistPayload: Decodable {
    let artist: Artist
}

struct PlaylistsPayload: Decodable {
    let playlists: Container

    struct Container: Decodable {
        let playlist: [Playlist]?
    }
}

struct PlaylistPayload: Decodable {
    let playlist: Playlist
}

struct Search3Payload: Decodable {
    let searchResult3: SearchResult3
}

struct RandomSongsPayload: Decodable {
    let randomSongs: SongList

    struct SongList: Decodable {
        let song: [Song]?
    }
}

struct Starred2Payload: Decodable {
    let starred2: Starred2

    struct Starred2: Decodable {
        let artist: [Artist]?
        let album: [Album]?
        let song: [Song]?
    }
}
