import SwiftUI

struct ArtistDetailView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController

    let id: String

    @State private var artist: Artist?
    @State private var failed = false

    var body: some View {
        ScrollView {
            if let artist {
                VStack(alignment: .leading, spacing: 24) {
                    header(artist)

                    if let albums = artist.album, !albums.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Discography")
                            AlbumGrid(albums: albums)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if failed {
                Text("Could not load this artist.")
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

    private func header(_ artist: Artist) -> some View {
        HStack(alignment: .center, spacing: 20) {
            Group {
                if let cover = artist.coverArt, let client = app.client {
                    AsyncImage(url: client.coverArtURL(id: cover, size: 360)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: 160, height: 160)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.5), radius: 16, y: 6)

            VStack(alignment: .leading, spacing: 8) {
                Text("ARTIST")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundColor(.spSubtext)
                Text(artist.name)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(2)
                if let count = artist.albumCount {
                    Text("\(count) albums")
                        .font(.system(size: 13))
                        .foregroundColor(.spSubtext)
                }

                Button {
                    playAll()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Play")
                            .fontWeight(.bold)
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.spAccentFill))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.spCardHover
            Image(systemName: "music.mic")
                .font(.system(size: 48))
                .foregroundColor(.spSubtext)
        }
    }

    /// Plays the artist's albums in order, newest first.
    private func playAll() {
        guard let client = app.client, let albums = artist?.album, !albums.isEmpty else { return }
        Task {
            var songs: [Song] = []
            let sorted = albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
            for album in sorted.prefix(20) {
                if let full = try? await client.album(id: album.id), let albumSongs = full.song {
                    songs.append(contentsOf: albumSongs)
                }
            }
            if !songs.isEmpty {
                player.play(songs)
            }
        }
    }

    private func load() async {
        guard let client = app.client else { return }
        do {
            artist = try await client.artist(id: id)
        } catch {
            failed = true
        }
    }
}
