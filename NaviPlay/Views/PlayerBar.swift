import SwiftUI

struct PlayerBar: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var router: Router

    @Binding var showQueue: Bool

    var body: some View {
        HStack(spacing: 16) {
            nowPlayingSection
                .frame(width: 280, alignment: .leading)

            centerSection
                .frame(maxWidth: .infinity)

            rightSection
                .frame(width: 240, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 92)
        .background(Color.spCard)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    // MARK: - Left: current track

    @ViewBuilder
    private var nowPlayingSection: some View {
        if let song = player.currentSong {
            HStack(spacing: 12) {
                ArtworkView(coverArt: song.coverArt, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let artist = song.artist {
                        Button {
                            if let artistId = song.artistId {
                                router.go(.artist(artistId))
                            }
                        } label: {
                            Text(artist)
                                .font(.system(size: 11))
                                .foregroundColor(.spSubtext)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    app.toggleStar(song)
                } label: {
                    Image(systemName: app.isStarred(song) ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundColor(app.isStarred(song) ? .spGreen : .spSubtext)
                }
                .buttonStyle(.plain)
                .help("Add to Liked Songs")
            }
        } else {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.spCardHover)
                    .frame(width: 56, height: 56)
                Text("Not playing")
                    .font(.system(size: 12))
                    .foregroundColor(.spSubtext)
            }
        }
    }

    // MARK: - Center: controls + seek

    private var centerSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 22) {
                controlButton(
                    icon: "shuffle",
                    size: 13,
                    active: player.shuffleEnabled,
                    help: "Shuffle"
                ) {
                    player.toggleShuffle()
                }

                controlButton(icon: "backward.end.fill", size: 14, help: "Previous") {
                    player.previous()
                }

                Button {
                    player.togglePlayPause()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 34, height: 34)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .buttonStyle(.plain)
                .help(player.isPlaying ? "Pause" : "Play")

                controlButton(icon: "forward.end.fill", size: 14, help: "Next") {
                    player.next()
                }

                controlButton(
                    icon: player.repeatMode == .one ? "repeat.1" : "repeat",
                    size: 13,
                    active: player.repeatMode != .off,
                    help: "Repeat"
                ) {
                    player.cycleRepeatMode()
                }
            }

            HStack(spacing: 10) {
                Text(formatTime(player.currentTime))
                    .font(.system(size: 11))
                    .foregroundColor(.spSubtext)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)

                SeekBar(
                    value: player.duration > 0 ? player.currentTime / player.duration : 0
                ) { fraction in
                    player.seek(to: fraction * player.duration)
                }
                .frame(maxWidth: 480)
                .disabled(player.currentSong == nil)

                Text(formatTime(player.duration))
                    .font(.system(size: 11))
                    .foregroundColor(.spSubtext)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .leading)
            }
        }
    }

    // MARK: - Right: queue + volume

    private var rightSection: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showQueue.toggle()
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 14))
                    .foregroundColor(showQueue ? .spGreen : .spSubtext)
            }
            .buttonStyle(.plain)
            .help("Queue")

            Image(systemName: volumeIcon)
                .font(.system(size: 13))
                .foregroundColor(.spSubtext)
                .frame(width: 18)

            SeekBar(
                value: player.volume,
                onChanging: { player.volume = $0 },
                onSeek: { player.volume = $0 }
            )
            .frame(width: 100)
        }
    }

    private var volumeIcon: String {
        switch player.volume {
        case 0: return "speaker.slash.fill"
        case ..<0.4: return "speaker.wave.1.fill"
        case ..<0.75: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    private func controlButton(icon: String,
                               size: CGFloat,
                               active: Bool = false,
                               help: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(active ? .spGreen : .spSubtext)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
