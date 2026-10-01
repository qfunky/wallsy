import SwiftUI
import UniformTypeIdentifiers

enum SidebarSection: Hashable {
    case home
    case search
    case tracks
    case artists
    case liked
    case downloads
    case stats
    case importCSV
    case playlist(String)
}

struct MainView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var router: Router

    @State private var showQueue = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Sidebar(selection: $router.selection)

                NavigationStack(path: $router.path) {
                    rootView
                        .navigationDestination(for: Route.self) { route in
                            destination(for: route)
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.spBackground)

                if showQueue {
                    QueueView()
                        .frame(width: 320)
                        .background(.ultraThinMaterial)
                        .overlay(alignment: .leading) {
                            Color.spBorder.frame(width: 1)
                        }
                        .transition(.move(edge: .trailing))
                }
            }

            PlayerBar(showQueue: $showQueue)
        }
        .background(Color.spBackground)
        .onChange(of: router.selection) {
            router.reset()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wallsySearch)) { _ in router.selection = .search }
        .onReceive(NotificationCenter.default.publisher(for: .wallsyHome)) { _ in router.selection = .home }
        .onReceive(NotificationCenter.default.publisher(for: .wallsyLiked)) { _ in router.selection = .liked }
        .onReceive(NotificationCenter.default.publisher(for: .wallsyQueue)) { _ in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showQueue.toggle() }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch router.selection {
        case .home:
            HomeView()
        case .search:
            SearchView()
        case .tracks:
            TracksView()
        case .artists:
            ArtistsView()
        case .liked:
            LikedSongsView()
        case .downloads:
            DownloadsView()
        case .stats:
            StatsView()
        case .importCSV:
            ImportView()
        case .playlist(let id):
            PlaylistDetailView(id: id)
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .album(let id):
            AlbumDetailView(id: id)
        case .artist(let id):
            ArtistDetailView(id: id)
        case .playlist(let id):
            PlaylistDetailView(id: id)
        case .liked:
            LikedSongsView()
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var router: Router
    @Binding var selection: SidebarSection

    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""

    /// Selecting an already-selected section pops any pushed detail views.
    private func select(_ section: SidebarSection) {
        if selection == section {
            router.reset()
        } else {
            selection = section
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 11) {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.spText)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.spAccentFill))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Wallsy")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.spText)
                    Text("YOUR MUSIC")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.7)
                        .foregroundColor(.spSubtext)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 20)

            sidebarButton(.home, icon: "house.fill", label: "Home")
            sidebarButton(.search, icon: "magnifyingglass", label: "Search")
            sidebarButton(.tracks, icon: "music.note.list", label: "Tracks")
            sidebarButton(.artists, icon: "music.mic", label: "Artists")
            sidebarButton(.liked, icon: "heart.fill", label: "Liked Songs")
            sidebarButton(.downloads, icon: "arrow.down.circle.fill", label: "Downloads")
            sidebarButton(.stats, icon: "chart.bar.fill", label: "Stats")
            sidebarButton(.importCSV, icon: "square.and.arrow.down.on.square", label: "Import")

            HStack {
                Text("PLAYLISTS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundColor(.spSubtext)
                Spacer()
                Button {
                    showNewPlaylist = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.spSubtext)
                }
                .buttonStyle(.plain)
                .help("New playlist")
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 6)
            .contextMenu {
                Button("New Playlist…") { showNewPlaylist = true }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(app.playlists) { playlist in
                        playlistButton(playlist)
                    }
                }
            }
            .contextMenu {
                Button("New Playlist…") { showNewPlaylist = true }
            }

            Spacer(minLength: 8)

            if app.isOffline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text("Offline")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                    Spacer()
                    Button {
                        Task { await app.retryConnection() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(.spSubtext)
                    }
                    .buttonStyle(.plain)
                    .help("Try to reconnect")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }

            Divider().background(Color.spBorder)

            HStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.spSubtext)
                Text(app.username)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.spText)
                    .lineLimit(1)
                Spacer()
                Button {
                    app.showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.spSubtext)
                }
                .buttonStyle(.plain)
                .help("Settings")
                Button {
                    router.selection = .home
                    router.reset()
                    app.logout()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13))
                        .foregroundColor(.spSubtext)
                }
                .buttonStyle(.plain)
                .help("Log out")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 246)
        .frame(maxHeight: .infinity)
        .background(Color.spCard)
        .overlay(alignment: .trailing) {
            Color.spBorder.frame(width: 1)
        }
        .alert("New Playlist", isPresented: $showNewPlaylist) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Create") {
                let name = newPlaylistName
                newPlaylistName = ""
                Task { await app.createPlaylist(named: name, songIds: []) }
            }
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
        }
    }

    private func sidebarButton(_ section: SidebarSection, icon: String, label: String) -> some View {
        SidebarRow(
            icon: icon,
            label: label,
            isSelected: selection == section
        ) {
            select(section)
        }
    }

    private func playlistButton(_ playlist: Playlist) -> some View {
        PlaylistSidebarRow(
            playlist: playlist,
            isSelected: selection == .playlist(playlist.id)
        ) {
            select(.playlist(playlist.id))
        }
    }
}

/// Sidebar playlist row that also accepts drops of dragged tracks
/// (payload: comma-separated song IDs).
private struct PlaylistSidebarRow: View {
    @EnvironmentObject private var app: AppState

    let playlist: Playlist
    let isSelected: Bool
    let action: () -> Void

    @State private var isDropTarget = false

    var body: some View {
        SidebarRow(
            icon: "music.note.list",
            label: playlist.name,
            isSelected: isSelected,
            action: action
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.spAccent, lineWidth: isDropTarget ? 1.5 : 0)
                .padding(.horizontal, 8)
        )
        .onDrop(of: [.plainText], isTargeted: $isDropTarget) { providers in
            guard let provider = providers.first else { return false }
            let playlistId = playlist.id
            let appRef = app
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let payload = object as? String else { return }
                let ids = payload.split(separator: ",").map(String.init)
                Task { @MainActor in
                    await appRef.addSongs(ids, toPlaylist: playlistId)
                }
            }
            return true
        }
    }
}

private struct SidebarRow: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(isSelected ? .spText : (hovering ? .spText : .spSubtext))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? Color.spAccentFill.opacity(0.7) : (hovering ? Color.spSubtleFill : Color.clear))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? Color.spAccent.opacity(0.28) : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering = $0 }
    }
}

// MARK: - Queue panel

struct QueueView: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.spText)
                Spacer()
                if player.queue.count > (player.currentIndex ?? -1) + 1 {
                    Button("Clear") {
                        player.clearUpcoming()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.spSubtext)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if player.queue.isEmpty {
                Spacer()
                Text("Nothing in the queue")
                    .font(.system(size: 13))
                    .foregroundColor(.spSubtext)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(player.queue.enumerated()), id: \.offset) { index, song in
                            QueueRow(
                                song: song,
                                isCurrent: index == player.currentIndex,
                                isPlaying: player.isPlaying
                            ) {
                                player.jump(to: index)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
    }
}

private struct QueueRow: View {
    let song: Song
    let isCurrent: Bool
    let isPlaying: Bool
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(coverArt: song.coverArt, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 13))
                    .foregroundColor(isCurrent ? .spAccent : .spText)
                    .lineLimit(1)
                Text(song.artist ?? "")
                    .font(.system(size: 11))
                    .foregroundColor(.spSubtext)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.spAccent)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(hovering ? Color.spSubtleFill : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onSelect)
        .onHover { hovering = $0 }
    }
}
