import SwiftUI

struct AlbumDetailView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var router: Router

    let id: String

    @State private var album: Album?
    @State private var failed = false

    private var songs: [Song] {
        album?.song ?? []
    }

    var body: some View {
        ScrollView {
            if let album {
                VStack(alignment: .leading, spacing: 20) {
                    header(album)
                    actions
                    trackList
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if failed {
                Text("Could not load this album.")
                    .foregroundColor(.spSubtext)
                    .padding(.top, 80)
                    .frame(maxWidth: .infinity)
            } else {
                ProgressView()
                    .padding(.top, 120)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color.spBackground)
        .task(id: id) { await load() }
    }

    private func header(_ album: Album) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            ArtworkView(coverArt: album.coverArt, size: 200, corner: 8)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("ALBUM")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundColor(.spSubtext)
                Text(album.name)
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    if let artistId = album.artistId, let artist = album.artist {
                        Button(artist) {
                            router.go(.artist(artistId))
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    } else if let artist = album.artist {
                        Text(artist)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text(metaLine(album))
                        .font(.system(size: 13))
                        .foregroundColor(.spSubtext)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 16) {
            PlayCircleButton(diameter: 52) {
                guard !songs.isEmpty else { return }
                player.play(songs)
            }
            Button {
                for song in songs {
                    player.addToQueue(song)
                }
            } label: {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 18))
                    .foregroundColor(.spSubtext)
            }
            .buttonStyle(.plain)
            .help("Add album to queue")
        }
    }

    private var trackList: some View {
        LazyVStack(spacing: 1) {
            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                TrackRow(song: song, index: index) {
                    player.play(songs, startAt: index)
                }
            }
        }
    }

    private func metaLine(_ album: Album) -> String {
        var parts: [String] = []
        if let year = album.year { parts.append(String(year)) }
        if let count = album.songCount { parts.append("\(count) songs") }
        if let duration = album.duration { parts.append(formatLongDuration(duration)) }
        return (parts.isEmpty ? "" : "• ") + parts.joined(separator: " • ")
    }

    private func load() async {
        guard let client = app.client else { return }
        do {
            album = try await client.album(id: id)
        } catch {
            failed = true
        }
    }
}
