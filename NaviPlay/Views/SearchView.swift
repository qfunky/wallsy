import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var router: Router

    @State private var query = ""
    @State private var result: SearchResult3?
    @State private var searching = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(24)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let result {
                        if isEmptyResult(result) {
                            Text("No results for \u{201C}\(query)\u{201D}")
                                .font(.system(size: 14))
                                .foregroundColor(.spSubtext)
                                .padding(.top, 40)
                                .frame(maxWidth: .infinity)
                        } else {
                            songsSection(result)
                            artistsSection(result)
                            albumsSection(result)
                        }
                    } else if !searching {
                        Text("Search your library for songs, albums and artists.")
                            .font(.system(size: 14))
                            .foregroundColor(.spSubtext)
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.spBackground)
        .task(id: query) {
            await performSearch()
        }
        .onAppear { fieldFocused = true }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(.spSubtext)
            TextField("What do you want to listen to?", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($fieldFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.spSubtext)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.white.opacity(0.1)))
        .frame(maxWidth: 420)
    }

    // MARK: - Result sections

    @ViewBuilder
    private func songsSection(_ result: SearchResult3) -> some View {
        if let songs = result.song, !songs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Songs")
                LazyVStack(spacing: 1) {
                    ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                        TrackRow(song: song, index: index, showsArtwork: true, showsAlbum: true) {
                            player.play(songs, startAt: index)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func artistsSection(_ result: SearchResult3) -> some View {
        if let artists = result.artist, !artists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Artists")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(artists) { artist in
                            ArtistCircle(artist: artist)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func albumsSection(_ result: SearchResult3) -> some View {
        if let albums = result.album, !albums.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Albums")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(albums) { album in
                            AlbumCard(album: album)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Logic

    private func isEmptyResult(_ result: SearchResult3) -> Bool {
        (result.song ?? []).isEmpty
            && (result.album ?? []).isEmpty
            && (result.artist ?? []).isEmpty
    }

    private func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let client = app.client else {
            result = nil
            return
        }
        // Debounce while the user is typing.
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }

        searching = true
        defer { searching = false }
        if let found = try? await client.search(trimmed), !Task.isCancelled {
            result = found
        }
    }
}

// MARK: - Artist circle card

struct ArtistCircle: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var router: Router

    let artist: Artist

    @State private var hovering = false

    var body: some View {
        Button {
            router.go(.artist(artist.id))
        } label: {
            VStack(spacing: 8) {
                Group {
                    if let cover = artist.coverArt, let client = app.client {
                        AsyncImage(url: client.coverArtURL(id: cover, size: 240)) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                artistPlaceholder
                            }
                        }
                    } else {
                        artistPlaceholder
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())

                Text(artist.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("Artist")
                    .font(.system(size: 11))
                    .foregroundColor(.spSubtext)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovering ? Color.spCardHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var artistPlaceholder: some View {
        ZStack {
            Color.spCardHover
            Image(systemName: "music.mic")
                .font(.system(size: 36))
                .foregroundColor(.spSubtext)
        }
    }
}
