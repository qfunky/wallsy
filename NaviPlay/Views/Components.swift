import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case emerald, forest, sage, graphite, midnight, charcoal, light

    static let storageKey = "appTheme"
    static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .emerald
    }

    var id: String { rawValue }
    var isLight: Bool { self == .light }

    var name: String {
        switch self {
        case .emerald: "Emerald"
        case .forest: "Forest"
        case .sage: "Sage"
        case .graphite: "Graphite"
        case .midnight: "Midnight"
        case .charcoal: "Charcoal"
        case .light: "Light"
        }
    }

    var group: String {
        switch self {
        case .emerald, .forest, .sage: "GREEN"
        case .graphite, .midnight, .charcoal: "DARK"
        case .light: "LIGHT"
        }
    }

    // Background, surface, hovered surface, accent, filled control, secondary text, primary text.
    private var values: [[Double]] {
        switch self {
        case .emerald:
            [[10,13,12], [19,24,22], [29,37,33], [128,177,151], [34,83,62], [164,174,167], [245,248,246]]
        case .forest:
            [[8,18,15], [15,31,25], [25,45,35], [138,193,159], [29,83,56], [157,181,166], [243,249,244]]
        case .sage:
            [[17,21,17], [29,36,29], [41,50,40], [167,194,158], [64,91,65], [169,181,165], [247,249,244]]
        case .graphite:
            [[13,14,16], [25,26,29], [38,39,43], [184,190,199], [63,67,74], [165,169,176], [247,248,250]]
        case .midnight:
            [[10,14,23], [20,26,39], [33,41,57], [155,176,211], [48,66,97], [155,166,183], [244,247,253]]
        case .charcoal:
            [[18,17,17], [31,29,29], [45,42,41], [204,186,169], [88,72,64], [175,166,161], [251,248,245]]
        case .light:
            [[246,248,246], [255,255,255], [233,239,234], [35,104,74], [215,234,221], [91,104,95], [25,37,30]]
        }
    }

    private func color(_ index: Int) -> Color {
        let rgb = values[index]
        return Color(red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255)
    }

    var background: Color { color(0) }
    var card: Color { color(1) }
    var cardHover: Color { color(2) }
    var accent: Color { color(3) }
    var accentFill: Color { color(4) }
    var subtext: Color { color(5) }
    var text: Color { color(6) }
    var border: Color { isLight ? Color.black.opacity(0.1) : Color.white.opacity(0.08) }
    var subtleFill: Color { isLight ? Color.black.opacity(0.055) : Color.white.opacity(0.08) }
}

extension Color {
    static var spBackground: Color { AppTheme.current.background }
    static var spCard: Color { AppTheme.current.card }
    static var spCardHover: Color { AppTheme.current.cardHover }
    static var spAccent: Color { AppTheme.current.accent }
    static var spAccentFill: Color { AppTheme.current.accentFill }
    static var spSubtext: Color { AppTheme.current.subtext }
    static var spText: Color { AppTheme.current.text }
    static var spBorder: Color { AppTheme.current.border }
    static var spSubtleFill: Color { AppTheme.current.subtleFill }
}

// MARK: - Formatting helpers

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds.rounded())
    let minutes = total / 60
    let secs = total % 60
    return String(format: "%d:%02d", minutes, secs)
}

func formatLongDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    if hours > 0 {
        return "\(hours) hr \(minutes) min"
    }
    return "\(minutes) min"
}

// MARK: - Artwork

struct ArtworkView: View {
    @EnvironmentObject private var app: AppState

    let coverArt: String?
    var size: CGFloat
    var corner: CGFloat = 4

    var body: some View {
        Group {
            if let coverArt, let client = app.client {
                AsyncImage(url: client.coverArtURL(id: coverArt, size: Int(size * 2))) { phase in
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
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Color.spCardHover
            Image(systemName: "music.note")
                .font(.system(size: size * 0.35))
                .foregroundColor(.spSubtext)
        }
    }
}

// MARK: - Playlist cover (custom local cover overrides server art)

struct PlaylistCoverView: View {
    @EnvironmentObject private var app: AppState

    let playlistId: String
    let coverArt: String?
    var size: CGFloat
    var corner: CGFloat = 4

    var body: some View {
        Group {
            if let url = app.customCoverURL(for: playlistId),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            } else {
                ArtworkView(coverArt: coverArt, size: size, corner: corner)
            }
        }
        .id(app.coverVersion) // re-render when a cover changes
    }
}

// MARK: - Play button overlay

struct PlayCircleButton: View {
    var diameter: CGFloat = 44
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.spAccentFill)
                    .frame(width: diameter, height: diameter)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                Image(systemName: "play.fill")
                    .font(.system(size: diameter * 0.4, weight: .bold))
                    .foregroundColor(.spText)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Album card

struct AlbumCard: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var router: Router

    let album: Album
    var artSize: CGFloat = 156

    @State private var hovering = false

    var body: some View {
        Button {
            router.go(.album(album.id))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    ArtworkView(coverArt: album.coverArt, size: artSize, corner: 10)
                    if hovering {
                        PlayCircleButton { playAlbum() }
                            .padding(8)
                            .transition(.opacity)
                    }
                }
                Text(album.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.spText)
                    .lineLimit(1)
                Text(albumSubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.spSubtext)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(width: artSize + 24, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(hovering ? Color.spCardHover : Color.spCard)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.spBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.15)) {
                hovering = inside
            }
        }
    }

    private var albumSubtitle: String {
        var parts: [String] = []
        if let year = album.year { parts.append(String(year)) }
        if let artist = album.artist { parts.append(artist) }
        return parts.joined(separator: " • ")
    }

    private func playAlbum() {
        guard let client = app.client else { return }
        Task {
            if let full = try? await client.album(id: album.id), let songs = full.song, !songs.isEmpty {
                player.play(songs)
            }
        }
    }
}

// MARK: - Track row

struct TrackRow: View {
    @AppStorage("compactLists") private var compactLists = false
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var downloads: DownloadManager

    let song: Song
    let index: Int
    var showsArtwork = false
    var showsAlbum = false
    var onPlay: () -> Void
    /// When set, shows "Remove from Playlist" in the context menu.
    var onRemove: (() -> Void)? = nil
    /// Highlight used by multi-select lists.
    var isSelected = false

    @State private var hovering = false

    private var isCurrent: Bool {
        player.currentSong?.id == song.id
    }

    /// Small status indicator: queued / downloading / available offline.
    @ViewBuilder
    private var downloadBadge: some View {
        switch downloads.status(for: song) {
        case .cached:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.spAccent)
                .help("Available offline")
        case .downloading(let progress):
            DownloadProgressCircle(progress: progress)
                .help("Downloading…")
        case .queued:
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundColor(.spSubtext)
                .help("Queued for download")
        case .notCached:
            EmptyView()
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if hovering {
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.spText)
                    }
                    .buttonStyle(.plain)
                } else if isCurrent {
                    Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.spAccent)
                } else {
                    Text(String(index + 1))
                        .font(.system(size: 13))
                        .foregroundColor(.spSubtext)
                        .monospacedDigit()
                }
            }
            .frame(width: 26, alignment: .center)

            if showsArtwork {
                ArtworkView(coverArt: song.coverArt, size: compactLists ? 30 : 40)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 14))
                    .foregroundColor(isCurrent ? .spAccent : .spText)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.system(size: 12))
                        .foregroundColor(.spSubtext)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            if showsAlbum, let albumName = song.album {
                Text(albumName)
                    .font(.system(size: 12))
                    .foregroundColor(.spSubtext)
                    .lineLimit(1)
                    .frame(maxWidth: 240, alignment: .leading)
            }

            downloadBadge
                .frame(width: 16)

            Text(formatTime(Double(song.duration ?? 0)))
                .font(.system(size: 12))
                .foregroundColor(.spSubtext)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)

            Button {
                app.toggleStar(song)
            } label: {
                Image(systemName: app.isStarred(song) ? "heart.fill" : "heart")
                    .font(.system(size: 12))
                    .foregroundColor(app.isStarred(song) ? .spAccent : .spSubtext)
                    .frame(width: 24, height: 26)
            }
            .buttonStyle(.plain)
            .opacity(hovering || app.isStarred(song) ? 1 : 0)
            .help(app.isStarred(song) ? "Remove from Liked Songs" : "Add to Liked Songs")

            Menu {
                trackActions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.spSubtext)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More options for \(song.title)")
            .accessibilityLabel("More options for \(song.title)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compactLists ? 3 : 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isSelected
                        ? Color.spAccent.opacity(0.22)
                        : (hovering ? Color.spSubtleFill : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onPlay)
        .onHover { hovering = $0 }
        .contextMenu {
            trackActions
        }
    }

    @ViewBuilder
    private var trackActions: some View {
            Button("Play") { onPlay() }
            Button("Play Next") { player.playNext(song) }
            Button("Add to Queue") { player.addToQueue(song) }
            Divider()
            Button("Add to Playlist…") {
                // Present after the menu closes; presenting inside a nested macOS menu can flicker.
                DispatchQueue.main.async { app.playlistPickerSong = song }
            }
            if let onRemove {
                Button("Remove from Playlist", role: .destructive) { onRemove() }
            }
            Divider()
            if let albumId = song.albumId {
                Button("Go to Album") { router.go(.album(albumId)) }
            }
            if let artistId = song.artistId {
                Button("Go to Artist") { router.go(.artist(artistId)) }
            }
            Divider()
            Button(app.isStarred(song) ? "Remove from Liked Songs" : "Add to Liked Songs") {
                app.toggleStar(song)
            }
    }
}

// MARK: - UI zoom container (Spotify-style interface scale)

struct ZoomContainer<Content: View>: View {
    let scale: Double
    @ViewBuilder var content: () -> Content

    var body: some View {
        if abs(scale - 1.0) < 0.01 {
            content()
        } else {
            GeometryReader { geo in
                content()
                    .frame(width: geo.size.width / scale, height: geo.size.height / scale)
                    .scaleEffect(scale, anchor: .topLeading)
            }
        }
    }
}

// MARK: - Reorderable row (drag the handle onto another row)

struct ReorderableRow<Content: View>: View {
    let index: Int
    let onMove: (Int, Int) -> Void
    @ViewBuilder var content: () -> Content

    @State private var hovering = false
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 4) {
            content()

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12))
                .foregroundColor(.spSubtext)
                .frame(width: 24, height: 30)
                .contentShape(Rectangle())
                .opacity(hovering ? 1 : 0.25)
                .onDrag {
                    NSItemProvider(object: "move:\(index)" as NSString)
                }
                .help("Drag to reorder")
        }
        .overlay(alignment: .top) {
            if isTargeted {
                Rectangle()
                    .fill(Color.spAccent)
                    .frame(height: 2)
            }
        }
        .onHover { hovering = $0 }
        .onDrop(of: [.plainText], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            let target = index
            let mover = onMove
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let payload = object as? String, payload.hasPrefix("move:"),
                      let source = Int(payload.dropFirst(5)) else { return }
                Task { @MainActor in
                    mover(source, target)
                }
            }
            return true
        }
    }
}

// MARK: - Seek / volume bar

struct SeekBar: View {
    /// Current progress, 0...1.
    var value: Double
    var activeColor: Color = .spText
    var accessibilityName: String = "Progress"
    /// Called continuously while dragging (used by the volume slider).
    var onChanging: ((Double) -> Void)? = nil
    var onSeek: (Double) -> Void

    @State private var hovering = false
    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let progress = dragValue ?? min(max(value, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.spSubtext.opacity(0.35))
                    .frame(height: 4)
                Capsule()
                    .fill(hovering || dragValue != nil ? Color.spAccent : activeColor)
                    .frame(width: width * progress, height: 4)
                if hovering || dragValue != nil {
                    Circle()
                        .fill(Color.spText)
                        .frame(width: 11, height: 11)
                        .offset(x: width * progress - 5.5)
                }
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let fraction = min(max(gesture.location.x / width, 0), 1)
                        dragValue = fraction
                        onChanging?(fraction)
                    }
                    .onEnded { gesture in
                        let final = min(max(gesture.location.x / width, 0), 1)
                        onSeek(final)
                        dragValue = nil
                    }
            )
        }
        .frame(height: 12)
        .onHover { hovering = $0 }
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
        .accessibilityValue("\(Int(min(max(value, 0), 1) * 100)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(value + 0.05, 1))
            case .decrement: onSeek(max(value - 0.05, 0))
            @unknown default: break
            }
        }
    }
}

// MARK: - Download progress widgets

/// Tiny circular progress ring for a single downloading track.
struct DownloadProgressCircle: View {
    var progress: Double
    var size: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.spBorder, lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(progress, 0.03))
                .stroke(Color.spAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.2), value: progress)
    }
}

/// Batch progress bar shown while a download queue is being processed.
struct DownloadProgressView: View {
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        if downloads.batchTotal > 0 {
            HStack(spacing: 8) {
                ProgressView(value: downloads.batchProgress)
                    .progressViewStyle(.linear)
                    .tint(.spAccent)
                    .frame(width: 140)
                Text("\(downloads.batchDone)/\(downloads.batchTotal)")
                    .font(.system(size: 11))
                    .foregroundColor(.spSubtext)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.spText)
    }
}

// MARK: - Album grid

struct AlbumGrid: View {
    let albums: [Album]

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(albums) { album in
                AlbumCard(album: album)
            }
        }
    }
}
