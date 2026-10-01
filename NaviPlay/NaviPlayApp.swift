import SwiftUI
import Combine

@main
struct NaviPlayApp: App {
    @StateObject private var app = AppState()
    @StateObject private var player = PlayerController()
    @StateObject private var router = Router()
    @StateObject private var downloads = DownloadManager()
    @AppStorage("uiScale") private var uiScale = 1.0
    @AppStorage("appTheme") private var themeName = AppTheme.emerald.rawValue

    init() {
        // AsyncImage uses URLSession.shared, separate from SubsonicClient's API cache.
        URLCache.shared.memoryCapacity = 64 * 1024 * 1024
        URLCache.shared.diskCapacity = 256 * 1024 * 1024
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(themeName)
                .environmentObject(app)
                .environmentObject(player)
                .environmentObject(router)
                .environmentObject(downloads)
                .preferredColorScheme(AppTheme(rawValue: themeName)?.isLight == true ? .light : .dark)
                .tint(.spAccent)
                .frame(minWidth: 1020, minHeight: 660)
                .sheet(isPresented: $app.showSettings) {
                    SettingsView()
                        .environmentObject(app)
                        .environmentObject(player)
                        .environmentObject(router)
                        .environmentObject(downloads)
                        .preferredColorScheme(AppTheme(rawValue: themeName)?.isLight == true ? .light : .dark)
                        .tint(.spAccent)
                }
                .sheet(item: $app.playlistPickerSong) { song in
                    PlaylistPickerView(song: song)
                        .environmentObject(app)
                        .preferredColorScheme(AppTheme(rawValue: themeName)?.isLight == true ? .light : .dark)
                        .tint(.spAccent)
                }
                .alert("Playlist", isPresented: Binding(
                    get: { app.playlistActionMessage != nil },
                    set: { if !$0 { app.playlistActionMessage = nil } }
                )) {
                    Button("OK") { app.playlistActionMessage = nil }
                } message: {
                    Text(app.playlistActionMessage ?? "")
                }
        }
        .commands {
            CommandMenu("Navigation") {
                Button("Search Library") {
                    NotificationCenter.default.post(name: .wallsySearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
                Button("Home") {
                    NotificationCenter.default.post(name: .wallsyHome, object: nil)
                }
                .keyboardShortcut("1", modifiers: [.command])
                Button("Liked Songs") {
                    NotificationCenter.default.post(name: .wallsyLiked, object: nil)
                }
                .keyboardShortcut("2", modifiers: [.command])
                Button("Toggle Queue") {
                    NotificationCenter.default.post(name: .wallsyQueue, object: nil)
                }
                .keyboardShortcut("j", modifiers: [.command])
            }
            CommandMenu("Playback") {
                Button(player.isPlaying ? "Pause" : "Play") {
                    player.togglePlayPause()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Next Track") { player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])

                Button("Previous Track") { player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])

                Divider()

                Button("Toggle Shuffle") { player.toggleShuffle() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Cycle Repeat Mode") { player.cycleRepeatMode() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Volume Up") { player.volume = min(player.volume + 0.05, 1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                Button("Volume Down") { player.volume = max(player.volume - 0.05, 0) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { uiScale = min((uiScale * 10).rounded() / 10 + 0.1, 1.3) }
                    .keyboardShortcut("+", modifiers: [.command])
                Button("Zoom Out") { uiScale = max((uiScale * 10).rounded() / 10 - 0.1, 0.7) }
                    .keyboardShortcut("-", modifiers: [.command])
                Button("Reset Zoom") { uiScale = 1.0 }
                    .keyboardShortcut("0", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let wallsySearch = Notification.Name("wallsy.search")
    static let wallsyHome = Notification.Name("wallsy.home")
    static let wallsyLiked = Notification.Name("wallsy.liked")
    static let wallsyQueue = Notification.Name("wallsy.queue")
}

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var downloads: DownloadManager

    @AppStorage("uiScale") private var uiScale = 1.0

    var body: some View {
        ZoomContainer(scale: uiScale) {
            Group {
                if app.client != nil {
                    MainView()
                } else {
                    LoginView()
                }
            }
        }
        .background(Color.spBackground)
        .task { await app.tryAutoLogin() }
        .onAppear { player.downloads = downloads }
        .onReceive(app.$client) { client in
            let wasConnected = player.client != nil
            player.client = client
            downloads.client = client
            if client == nil {
                if wasConnected { player.stopAndClear() }
            } else {
                player.restoreSessionIfAvailable()
                // Heal any cached files that are missing metadata.
                Task { await downloads.reconcileMissingMetadata() }
            }
        }
    }
}
