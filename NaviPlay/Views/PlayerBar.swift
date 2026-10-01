import SwiftUI

struct PlayerBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .frame(height: 88)
        .background(Color.spCard)
        .overlay(alignment: .top) {
            Color.spBorder.frame(height: 1)
        }
    }

    // MARK: - Left: current track

    @ViewBuilder
    private var nowPlayingSection: some View {
        if let song = player.currentSong {
            HStack(spacing: 12) {
                ArtworkView(coverArt: song.coverArt, size: 54, corner: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.spText)
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
                        .foregroundColor(app.isStarred(song) ? .spAccent : .spSubtext)
                }
                .buttonStyle(.plain)
                .help("Add to Liked Songs")
            }
        } else {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.spCardHover)
                    .frame(width: 54, height: 54)
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
                            .fill(Color.spAccentFill)
                            .frame(width: 38, height: 38)
                            .shadow(color: Color.spAccentFill.opacity(0.2), radius: 8, y: 2)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.spText)
                    }
                }
                .buttonStyle(.plain)
                .help(player.isPlaying ? "Pause" : "Play")
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

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
                    value: player.duration > 0 ? player.currentTime / player.duration : 0,
                    accessibilityName: "Playback position"
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
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    showQueue.toggle()
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 14))
                    .foregroundColor(showQueue ? .spAccent : .spSubtext)
            }
            .buttonStyle(.plain)
            .help("Queue")
            .accessibilityLabel(showQueue ? "Hide queue" : "Show queue")

            Image(systemName: volumeIcon)
                .font(.system(size: 13))
                .foregroundColor(.spSubtext)
                .frame(width: 18)

            SeekBar(
                value: player.volume,
                accessibilityName: "Volume",
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
                .foregroundColor(active ? .spAccent : .spSubtext)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
