import SwiftUI
import UniformTypeIdentifiers

struct PlaylistDetailView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var downloads: DownloadManager

    let id: String

    @State private var playlist: Playlist?
    @State private var songs: [Song] = []
    @State private var failed = false
    @State private var showDeleteConfirm = false
    @State private var showCoverPicker = false

    var body: some View {
        Group {
            if playlist != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(playlist!)
                            .padding(.bottom, 16)
                        actions
                            .padding(.bottom, 16)

                        LazyVStack(spacing: 1) {
                            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                                ReorderableRow(
                                    index: index,
                                    onMove: { from, to in moveSong(from: from, to: to) }
                                ) {
                                    TrackRow(
                                        song: song,
                                        index: index,
                                        showsArtwork: true,
                                        showsAlbum: true,
                                        onPlay: { player.play(songs, startAt: index) },
                                        onRemove: { remove(at: index) }
                                    )
                                }
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if failed {
                Text("Could not load this playlist.")
                    .foregroundColor(.spSubtext)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.spBackground)
        .task(id: id) { await load() }
        .confirmationDialog(
            "Delete \u{201C}\(playlist?.name ?? "playlist")\u{201D}?",
            isPresented: $showDeleteConfirm
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await app.deletePlaylist(id)
                    router.reset()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $showCoverPicker, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                app.setCustomCover(from: url, for: id)
            }
        }
    }

    // MARK: - Header & actions

    private func header(_ playlist: Playlist) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            PlaylistCoverView(playlistId: id, coverArt: playlist.coverArt, size: 200, corner: 8)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                .onTapGesture { showCoverPicker = true }
                .help("Click to choose a custom cover")

            VStack(alignment: .leading, spacing: 8) {
                Text("PLAYLIST")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundColor(.spSubtext)
                Text(playlist.name)
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(2)
                if let comment = playlist.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.system(size: 13))
                        .foregroundColor(.spSubtext)
                        .lineLimit(2)
                }
                Text(metaLine(playlist))
                    .font(.system(size: 13))
                    .foregroundColor(.spSubtext)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 16) {
            PlayCircleButton(diameter: 52) {
                guard !songs.isEmpty else { return }
                player.play(songs)
            }

            downloadButton

            Menu {
                Button("Change Cover…") { showCoverPicker = true }
                if app.customCoverURL(for: id) != nil {
                    Button("Remove Custom Cover") { app.removeCustomCover(for: id) }
                }
                Divider()
                Button("Delete Playlist", role: .destructive) {
                    showDeleteConfirm = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18))
                    .foregroundColor(.spSubtext)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if downloads.activeCount > 0 {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Downloading \(downloads.activeCount)…")
                        .font(.system(size: 11))
                        .foregroundColor(.spSubtext)
                }
            }

            Spacer()

            Text("Drag tracks to reorder")
                .font(.system(size: 11))
                .foregroundColor(.spSubtext.opacity(0.7))
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        if downloads.allCached(songs) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.spGreen)
                .help("Available offline")
        } else {
            Button {
                downloads.download(songs)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.spSubtext)
            }
            .buttonStyle(.plain)
            .help("Download for offline playback")
            .disabled(songs.isEmpty)
        }
    }

    // MARK: - Actions

    private func moveSong(from source: Int, to destination: Int) {
        guard source != destination,
              songs.indices.contains(source),
              songs.indices.contains(destination) else { return }
        let item = songs.remove(at: source)
        songs.insert(item, at: destination)
        syncOrder()
    }

    private func remove(at index: Int) {
        guard songs.indices.contains(index) else { return }
        songs.remove(at: index)
        syncOrder()
    }

    /// Pushes the local order to the server by replacing the playlist contents.
    private func syncOrder() {
        guard let client = app.client else { return }
        let ids = songs.map(\.id)
        Task {
            try? await client.replacePlaylist(id: id, songIds: ids)
            await app.refreshLibrary()
        }
    }

    private func metaLine(_ playlist: Playlist) -> String {
        var parts: [String] = []
        if let owner = playlist.owner { parts.append(owner) }
        parts.append("\(songs.count) songs")
        if let duration = playlist.duration { parts.append(formatLongDuration(duration)) }
        return parts.joined(separator: " • ")
    }

    private func load() async {
        guard let client = app.client else { return }
        failed = false
        do {
            let loaded = try await client.playlist(id: id)
            playlist = loaded
            songs = loaded.entry ?? []
        } catch {
            failed = true
        }
    }
}

// MARK: - Liked songs

struct LikedSongsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var downloads: DownloadManager

    @State private var songs: [Song] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom, spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.27, green: 0.16, blue: 0.9), Color(red: 0.7, green: 0.75, blue: 0.95)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 200, height: 200)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.white)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PLAYLIST")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.4)
                            .foregroundColor(.spSubtext)
                        Text("Liked Songs")
                            .font(.system(size: 36, weight: .heavy))
                            .foregroundColor(.white)
                        Text("\(songs.count) songs")
                            .font(.system(size: 13))
                            .foregroundColor(.spSubtext)
                    }
                }

                HStack(spacing: 16) {
                    PlayCircleButton(diameter: 52) {
                        guard !songs.isEmpty else { return }
                        player.play(songs)
                    }
                    if downloads.allCached(songs) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.spGreen)
                    } else {
                        Button {
                            downloads.download(songs)
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 24))
                                .foregroundColor(.spSubtext)
                        }
                        .buttonStyle(.plain)
                        .disabled(songs.isEmpty)
                    }
                }

                if loaded && songs.isEmpty {
                    Text("Songs you like will appear here. Click the heart on any track.")
                        .font(.system(size: 13))
                        .foregroundColor(.spSubtext)
                        .padding(.top, 12)
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                            TrackRow(song: song, index: index, showsArtwork: true, showsAlbum: true) {
                                player.play(songs, startAt: index)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.spBackground)
        .task { await load() }
    }

    private func load() async {
        guard let client = app.client else { return }
        songs = (try? await client.starredSongs()) ?? []
        loaded = true
    }
}
