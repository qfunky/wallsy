import SwiftUI

/// Shows everything in the offline cache. Fully functional without a network
/// connection — playback uses the local files.
struct DownloadsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var downloads: DownloadManager

    private var songs: [Song] {
        downloads.cachedSongs
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom, spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.05, green: 0.35, blue: 0.18), Color.spGreen],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 200, height: 200)
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.white)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("OFFLINE")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.4)
                            .foregroundColor(.spSubtext)
                        Text("Downloads")
                            .font(.system(size: 36, weight: .heavy))
                            .foregroundColor(.white)
                        Text("\(songs.count) tracks • \(ByteCountFormatter.string(fromByteCount: downloads.cacheSizeBytes, countStyle: .file))")
                            .font(.system(size: 13))
                            .foregroundColor(.spSubtext)
                        if app.isOffline {
                            Text("You're offline — these tracks still play.")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                    }
                }

                if !songs.isEmpty {
                    HStack(spacing: 16) {
                        PlayCircleButton(diameter: 52) {
                            player.play(songs)
                        }
                        DownloadProgressView()
                    }
                }

                if songs.isEmpty {
                    Text("Nothing downloaded yet. Open a playlist and press the ⬇ button to make it available offline.")
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
        .onAppear { downloads.refresh() }
        .task { await downloads.reconcileMissingMetadata() }
    }
}
