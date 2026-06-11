import SwiftUI
import Combine

@main
struct NaviPlayApp: App {
    @StateObject private var app = AppState()
    @StateObject private var player = PlayerController()
    @StateObject private var router = Router()
    @StateObject private var downloads = DownloadManager()
    @AppStorage("uiScale") private var uiScale = 1.0

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(player)
                .environmentObject(router)
                .environmentObject(downloads)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1020, minHeight: 660)
        }
        .commands {
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
            player.client = client
            downloads.client = client
            if client == nil {
                player.stopAndClear()
            }
        }
    }
}
