import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - All tracks (multi-select, playlist building)

struct TracksView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController

    @State private var songs: [Song] = []
    @State private var visibleSongs: [Song] = []
    @State private var loaded = false
    @State private var filter = ""
    @State private var selection: Set<String> = []
    @State private var anchorIndex: Int?
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""

    private func applyFilter() {
        let trimmed = filter.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty {
            visibleSongs = songs
        } else {
            visibleSongs = songs.filter {
                $0.title.lowercased().contains(trimmed)
                    || ($0.artist ?? "").lowercased().contains(trimmed)
                    || ($0.album ?? "").lowercased().contains(trimmed)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)

            if !loaded {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView("Loading your library…")
                    Spacer()
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(visibleSongs.enumerated()), id: \.offset) { index, song in
                            TrackRow(
                                song: song,
                                index: index,
                                showsArtwork: true,
                                showsAlbum: true,
                                onPlay: { player.play(visibleSongs, startAt: index) },
                                isSelected: selection.contains(song.id)
                            )
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    handleClick(index: index, song: song)
                                }
                            )
                            .onDrag { dragProvider(for: song) }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
            }
        }
        .background(Color.spBackground)
        .task { await load() }
        .onChange(of: filter) {
            applyFilter()
        }
        .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Create") {
                let ids = orderedSelectionIds()
                let name = newPlaylistName
                Task { await app.createPlaylist(named: name, songIds: ids) }
                newPlaylistName = ""
                selection = []
            }
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
        } message: {
            Text("Create a playlist with \(selection.count) selected track(s).")
        }
    }

    // MARK: - Selection (click / ⌘click / ⇧click)

    private func handleClick(index: Int, song: Song) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if selection.contains(song.id) {
                selection.remove(song.id)
            } else {
                selection.insert(song.id)
            }
            anchorIndex = index
        } else if modifiers.contains(.shift), let anchor = anchorIndex {
            let range = min(anchor, index)...max(anchor, index)
            let visible = visibleSongs
            for i in range where visible.indices.contains(i) {
                selection.insert(visible[i].id)
            }
        } else {
            if selection == [song.id] {
                selection = []
                anchorIndex = nil
            } else {
                selection = [song.id]
                anchorIndex = index
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tracks")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.spText)
                if loaded {
                    Text("\(songs.count)")
                        .font(.system(size: 14))
                        .foregroundColor(.spSubtext)
                }
                Spacer()
            }

            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.spSubtext)
                    TextField("Filter tracks", text: $filter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.spSubtleFill))
                .frame(maxWidth: 280)

                Text(selection.isEmpty ? "No selection" : "\(selection.count) selected")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(selection.isEmpty ? .spSubtext : .spAccent)
                    .frame(width: 90, alignment: .leading)

                Button {
                    let selected = orderedSelection()
                    if !selected.isEmpty {
                        player.play(selected)
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(selection.isEmpty ? .spSubtext : .spText)
                .disabled(selection.isEmpty)

                Menu {
                    Button("New Playlist…") {
                        showNewPlaylistAlert = true
                    }
                    if !app.playlists.isEmpty {
                        Divider()
                        ForEach(app.playlists) { playlist in
                            Button(playlist.name) {
                                let ids = orderedSelectionIds()
                                Task { await app.addSongs(ids, toPlaylist: playlist.id) }
                                selection = []
                            }
                        }
                    }
                } label: {
                    Label("Add to Playlist", systemImage: "text.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .foregroundColor(selection.isEmpty ? .spSubtext : .spText)
                .disabled(selection.isEmpty)

                Button("Deselect") {
                    selection = []
                    anchorIndex = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.spSubtext)
                .opacity(selection.isEmpty ? 0 : 1)
            }

            if loaded {
                Text("Click to select, ⌘-click to add, ⇧-click for a range. Double-click plays. Drag selected tracks onto a sidebar playlist.")
                    .font(.system(size: 11))
                    .foregroundColor(.spSubtext.opacity(0.8))
            }
        }
    }

    // MARK: - Helpers

    private func orderedSelection() -> [Song] {
        visibleSongs.filter { selection.contains($0.id) }
    }

    private func orderedSelectionIds() -> [String] {
        orderedSelection().map(\.id)
    }

    private func dragProvider(for song: Song) -> NSItemProvider {
        let ids: [String]
        if selection.contains(song.id) {
            ids = orderedSelectionIds()
        } else {
            ids = [song.id]
        }
        return NSItemProvider(object: ids.joined(separator: ",") as NSString)
    }

    private func load() async {
        guard !loaded, let client = app.client else { return }
        songs = (try? await client.allSongs()) ?? []
        applyFilter()
        loaded = true
    }
}

// MARK: - All artists

struct ArtistsView: View {
    @EnvironmentObject private var app: AppState

    @State private var indexes: [ArtistIndex] = []
    @State private var loaded = false

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Artists")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.spText)

                if !loaded {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 80)
                } else if indexes.isEmpty {
                    Text("No artists in your library yet.")
                        .font(.system(size: 14))
                        .foregroundColor(.spSubtext)
                } else {
                    ForEach(indexes, id: \.name) { index in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(index.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.spSubtext)
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                                ForEach(index.artist) { artist in
                                    ArtistCircle(artist: artist)
                                }
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
        guard !loaded, let client = app.client else { return }
        indexes = (try? await client.artists()) ?? []
        loaded = true
    }
}
