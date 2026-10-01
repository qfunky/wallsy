import SwiftUI

struct PlaylistPickerView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    let song: Song
    @State private var addingTo: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Add to Playlist")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.spText)
                    Text(song.title + (song.artist.map { " · \($0)" } ?? ""))
                        .font(.system(size: 12))
                        .foregroundColor(.spSubtext)
                        .lineLimit(1)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.spSubtext)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close playlist picker")
            }
            .padding(24)

            Rectangle().fill(Color.spBorder).frame(height: 1)

            if app.playlists.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list", description: Text("Create a playlist with the + button in the sidebar, then try again."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(app.playlists) { playlist in
                            Button {
                                guard addingTo == nil else { return }
                                addingTo = playlist.id
                                dismiss()
                                Task { await app.addSongs([song.id], toPlaylist: playlist.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "music.note.list")
                                        .font(.system(size: 15))
                                        .foregroundColor(.spAccent)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.spText)
                                        Text("\(playlist.songCount ?? 0) tracks")
                                            .font(.system(size: 11))
                                            .foregroundColor(.spSubtext)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.spSubtext)
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.spCard))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(addingTo != nil)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 440, height: 450)
        .background(Color.spBackground)
        .task { await app.refreshLibrary() }
    }
}
