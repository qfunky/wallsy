import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var router: Router

    @State private var recentlyPlayed: [Album] = []
    @State private var newest: [Album] = []
    @State private var mostPlayed: [Album] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR LIBRARY")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2.2)
                        .foregroundColor(.spAccent)
                    Text(greeting)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.spText)
                    Text("Pick up where the music left off.")
                        .font(.system(size: 13))
                        .foregroundColor(.spSubtext)
                }
                .padding(.top, 8)

                if app.isOffline {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(.orange)
                        Text("You're offline. Downloaded tracks are available in the Downloads tab.")
                            .font(.system(size: 13))
                            .foregroundColor(.spText)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.15)))
                }

                playlistPills

                if !loaded {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 60)
                } else {
                    shelf("Recently played", albums: recentlyPlayed)
                    shelf("Most played", albums: mostPlayed)
                    shelf("Recently added", albums: newest)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color.spAccentFill.opacity(AppTheme.current.isLight ? 0.3 : 0.45), location: 0),
                    .init(color: Color.spBackground, location: 0.50),
                    .init(color: Color.spBackground, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .task { await load() }
    }

    // MARK: - Spotify-style playlist pill grid

    private var playlistPills: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            PillCard(title: "Liked Songs", coverArt: nil, isLiked: true, playlistId: nil) {
                router.go(.liked)
            }
            ForEach(app.playlists.prefix(7)) { playlist in
                PillCard(title: playlist.name, coverArt: playlist.coverArt, isLiked: false, playlistId: playlist.id) {
                    router.go(.playlist(playlist.id))
                }
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    // MARK: - Album shelves

    @ViewBuilder
    private func shelf(_ title: String, albums: [Album]) -> some View {
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title)
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

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private func load() async {
        guard let client = app.client else { return }
        async let recent = client.albumList(type: .recent, size: 15)
        async let added = client.albumList(type: .newest, size: 15)
        async let frequent = client.albumList(type: .frequent, size: 15)

        recentlyPlayed = (try? await recent) ?? []
        newest = (try? await added) ?? []
        mostPlayed = (try? await frequent) ?? []
        loaded = true
    }
}

// MARK: - Pill card (Spotify home style)

private struct PillCard: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController

    let title: String
    let coverArt: String?
    let isLiked: Bool
    let playlistId: String?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                cover
                    .frame(width: 52, height: 52)
                    .clipped()

                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.spText)
                    .lineLimit(2)
                    .padding(.horizontal, 12)

                Spacer(minLength: 0)

                if hovering {
                    PlayCircleButton(diameter: 36) { play() }
                        .padding(.trailing, 10)
                        .transition(.opacity)
                }
            }
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovering ? Color.spCardHover : Color.spCard)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.12)) {
                hovering = inside
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        if isLiked {
            ZStack {
                LinearGradient(
                    colors: [Color.spAccentFill, Color.spCardHover],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "heart.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.spText)
            }
        } else if let playlistId {
            PlaylistCoverView(playlistId: playlistId, coverArt: coverArt, size: 52, corner: 0)
        } else {
            ArtworkView(coverArt: coverArt, size: 52, corner: 0)
        }
    }

    private func play() {
        guard let client = app.client else { return }
        Task {
            let songs: [Song]
            if isLiked {
                songs = (try? await client.starredSongs()) ?? []
            } else if let playlistId {
                songs = (try? await client.playlist(id: playlistId))?.entry ?? []
            } else {
                songs = []
            }
            if !songs.isEmpty {
                player.play(songs)
            }
        }
    }
}
