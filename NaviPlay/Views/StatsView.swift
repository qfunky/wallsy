import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var router: Router

    @State private var songs: [Song] = []
    @State private var topAlbums: [Album] = []
    @State private var loaded = false

    private var totalPlays: Int {
        songs.reduce(0) { $0 + ($1.playCount ?? 0) }
    }

    private var totalDuration: Int {
        songs.reduce(0) { $0 + ($1.duration ?? 0) }
    }

    private var topTracks: [Song] {
        songs
            .filter { ($0.playCount ?? 0) > 0 }
            .sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
            .prefix(15)
            .map { $0 }
    }

    private var topArtists: [(name: String, id: String?, plays: Int)] {
        var plays: [String: (id: String?, count: Int)] = [:]
        for song in songs {
            guard let artist = song.artist, let count = song.playCount, count > 0 else { continue }
            let existing = plays[artist]
            plays[artist] = (song.artistId ?? existing?.id, (existing?.count ?? 0) + count)
        }
        return plays
            .map { (name: $0.key, id: $0.value.id, plays: $0.value.count) }
            .sorted { $0.plays > $1.plays }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Statistics")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)

                if !loaded {
                    HStack {
                        Spacer()
                        ProgressView("Crunching the numbers…")
                        Spacer()
                    }
                    .padding(.top, 80)
                } else {
                    totalsRow

                    if !topTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Top tracks")
                            LazyVStack(spacing: 1) {
                                ForEach(Array(topTracks.enumerated()), id: \.offset) { index, song in
                                    HStack(spacing: 10) {
                                        TrackRow(song: song, index: index, showsArtwork: true, showsAlbum: true) {
                                            player.play(topTracks, startAt: index)
                                        }
                                        Text("\(song.playCount ?? 0) plays")
                                            .font(.system(size: 12))
                                            .foregroundColor(.spAccent)
                                            .frame(width: 70, alignment: .trailing)
                                            .monospacedDigit()
                                    }
                                }
                            }
                        }
                    }

                    if !topArtists.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Top artists")
                            LazyVStack(spacing: 1) {
                                ForEach(Array(topArtists.enumerated()), id: \.offset) { index, entry in
                                    Button {
                                        if let id = entry.id {
                                            router.go(.artist(id))
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Text(String(index + 1))
                                                .font(.system(size: 13))
                                                .foregroundColor(.spSubtext)
                                                .frame(width: 26)
                                                .monospacedDigit()
                                            Text(entry.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                            Spacer()
                                            Text("\(entry.plays) plays")
                                                .font(.system(size: 12))
                                                .foregroundColor(.spAccent)
                                                .monospacedDigit()
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if !topAlbums.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Most played albums")
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 14) {
                                    ForEach(topAlbums) { album in
                                        AlbumCard(album: album)
                                    }
                                }
                            }
                        }
                    }

                    if totalPlays == 0 {
                        Text("No play history yet — listen to some music and check back.")
                            .font(.system(size: 13))
                            .foregroundColor(.spSubtext)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.spBackground)
        .task { await load() }
    }

    private var totalsRow: some View {
        HStack(spacing: 12) {
            statCard(value: "\(songs.count)", label: "tracks in library")
            statCard(value: formatLongDuration(totalDuration), label: "of music")
            statCard(value: "\(totalPlays)", label: "total plays")
            statCard(value: "\(songs.filter { app.starredSongIDs.contains($0.id) }.count)", label: "liked songs")
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(.spAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.spSubtext)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.spCard))
    }

    private func load() async {
        guard !loaded, let client = app.client else { return }
        async let all = client.allSongs()
        async let frequent = client.albumList(type: .frequent, size: 15)
        songs = (try? await all) ?? []
        topAlbums = (try? await frequent) ?? []
        loaded = true
    }
}
