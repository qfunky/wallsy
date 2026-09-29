import Foundation

struct ServerSongFingerprint {
    let song: Song
    let digest: String
    let size: Int64
}

struct DuplicateGroup: Identifiable {
    let id: String
    let songs: [Song]
    let bytesPerSong: Int64

    var recoverableBytes: Int64 { Int64(songs.count - 1) * bytesPerSong }

    /// Subsonic paths may be virtual. Equal paths make file-level cleanup
    /// ambiguous even when the streamed bytes and server IDs match.
    var hasSameReportedPath: Bool {
        let paths = songs.compactMap(\.path)
        return paths.count == songs.count && Set(paths).count == 1
    }
}

/// Compares the original bytes streamed by Navidrome. File size only limits
/// which songs need downloading; SHA-256 decides whether they are duplicates.
enum DuplicateScanner {
    static func candidates(from songs: [Song]) -> [Song] {
        let buckets = Dictionary(grouping: songs.filter { ($0.size ?? 0) > 0 }, by: { $0.size! })
        return buckets.values
            .filter { $0.count > 1 }
            .flatMap { $0 }
            .sorted { ($0.size ?? 0) > ($1.size ?? 0) }
    }

    static func exactGroups(from fingerprints: [ServerSongFingerprint]) -> [DuplicateGroup] {
        let buckets = Dictionary(grouping: fingerprints, by: { "\($0.size):\($0.digest)" })
        return buckets.values.compactMap { matches in
            guard matches.count > 1, let first = matches.first else { return nil }
            return DuplicateGroup(
                id: "\(first.size):\(first.digest)",
                songs: matches.map(\.song).sorted { $0.id < $1.id },
                bytesPerSong: first.size
            )
        }
        .sorted { $0.recoverableBytes > $1.recoverableBytes }
    }
}
