import Foundation
import SwiftUI

enum Route: Hashable {
    case album(String)
    case artist(String)
    case playlist(String)
    case liked
}

@MainActor
final class Router: ObservableObject {
    @Published var path: [Route] = []
    @Published var selection: SidebarSection = .home

    func go(_ route: Route) {
        path.append(route)
    }

    func reset() {
        path = []
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var client: SubsonicClient?
    @Published private(set) var isOffline = false
    @Published var isBusy = false
    @Published var loginError: String?
    @Published var playlists: [Playlist] = []
    @Published var showSettings = false
    @Published var playlistPickerSong: Song?
    @Published var playlistActionMessage: String?
    @Published var starredSongIDs: Set<String> = []
    /// Bumped whenever a custom playlist cover changes, to refresh views.
    @Published var coverVersion = 0

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let server = "serverURL"
        static let username = "username"
        static let recents = "recentLogins"
    }

    struct RecentLogin: Codable, Hashable, Identifiable {
        var server: String
        var username: String
        var id: String { "\(server)|\(username)" }
    }

    /// Recent server/user pairs — no passwords stored.
    var recentLogins: [RecentLogin] {
        guard let data = defaults.data(forKey: Keys.recents),
              let list = try? JSONDecoder().decode([RecentLogin].self, from: data) else {
            return []
        }
        return list
    }

    private func recordRecentLogin(server: String, username: String) {
        var list = recentLogins
        let entry = RecentLogin(server: server, username: username)
        list.removeAll { $0 == entry }
        list.insert(entry, at: 0)
        if list.count > 8 { list = Array(list.prefix(8)) }
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: Keys.recents)
        }
    }

    var username: String {
        defaults.string(forKey: Keys.username) ?? client?.config.username ?? ""
    }

    // MARK: - Login / logout

    func tryAutoLogin() async {
        guard client == nil,
              let server = defaults.string(forKey: Keys.server),
              let user = defaults.string(forKey: Keys.username),
              let url = URL(string: server),
              let password = Keychain.read(account: "\(server)|\(user)") else {
            return
        }
        await connect(url: url, username: user, password: password, persist: false)
    }

    func login(server: String, username: String, password: String, remember: Bool) async {
        var address = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while address.hasSuffix("/") { address.removeLast() }
        if !address.contains("://") {
            address = "http://" + address
        }
        guard let url = URL(string: address), url.host != nil else {
            loginError = "Invalid server URL."
            return
        }
        await connect(url: url, username: username, password: password, persist: remember)
    }

    private func connect(url: URL, username: String, password: String, persist: Bool) async {
        isBusy = true
        loginError = nil
        defer { isBusy = false }

        let candidate = SubsonicClient(
            config: ServerConfig(baseURL: url, username: username, password: password)
        )
        do {
            try await candidate.ping()
            client = candidate
            isOffline = false
            recordRecentLogin(server: url.absoluteString, username: username)
            if persist {
                defaults.set(url.absoluteString, forKey: Keys.server)
                defaults.set(username, forKey: Keys.username)
                Keychain.save(account: "\(url.absoluteString)|\(username)", value: password)
            }
            await refreshLibrary()
        } catch {
            if persist {
                loginError = error.localizedDescription
            } else {
                // Auto-login with saved credentials but no network:
                // enter offline mode so cached downloads remain playable.
                client = candidate
                isOffline = true
            }
        }
    }

    /// Tries to leave offline mode by pinging the server again.
    func retryConnection() async {
        guard isOffline, let current = client else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await current.ping()
            isOffline = false
            await refreshLibrary()
        } catch {
            // still offline
        }
    }

    func logout() {
        if let server = defaults.string(forKey: Keys.server),
           let user = defaults.string(forKey: Keys.username) {
            Keychain.delete(account: "\(server)|\(user)")
        }
        defaults.removeObject(forKey: Keys.server)
        defaults.removeObject(forKey: Keys.username)
        client = nil
        playlists = []
        starredSongIDs = []
    }

    // MARK: - Library

    func refreshLibrary() async {
        guard let client else { return }
        async let playlistsTask = client.playlists()
        async let starredTask = client.starredSongs()
        if let latestPlaylists = try? await playlistsTask {
            playlists = latestPlaylists
        }
        if let latestStarred = try? await starredTask {
            starredSongIDs = Set(latestStarred.map(\.id))
        }
    }

    // MARK: - Custom playlist covers (stored locally; the server has no API for this)

    private var coversDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Wallsy/covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func customCoverURL(for playlistId: String) -> URL? {
        let url = coversDirectory.appendingPathComponent("\(playlistId).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func setCustomCover(from source: URL, for playlistId: String) {
        let dest = coversDirectory.appendingPathComponent("\(playlistId).png")
        try? FileManager.default.removeItem(at: dest)
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.copyItem(at: source, to: dest)
        coverVersion += 1
    }

    func removeCustomCover(for playlistId: String) {
        let dest = coversDirectory.appendingPathComponent("\(playlistId).png")
        try? FileManager.default.removeItem(at: dest)
        coverVersion += 1
    }

    // MARK: - Playlist editing

    func createPlaylist(named name: String, songIds: [String]) async {
        guard let client, !name.isEmpty else { return }
        try? await client.createPlaylist(name: name, songIds: songIds)
        await refreshLibrary()
    }

    func addSongs(_ songIds: [String], toPlaylist playlistId: String) async {
        guard let client, !songIds.isEmpty else { return }
        do {
            try await client.addToPlaylist(id: playlistId, songIds: songIds)
            await refreshLibrary()
            let count = songIds.count
            playlistActionMessage = count == 1 ? "Track added to playlist." : "\(count) tracks added to playlist."
        } catch {
            playlistActionMessage = "Could not add to playlist: \(error.localizedDescription)"
        }
    }

    func deletePlaylist(_ playlistId: String) async {
        guard let client else { return }
        try? await client.deletePlaylist(id: playlistId)
        await refreshLibrary()
    }

    func isStarred(_ song: Song) -> Bool {
        starredSongIDs.contains(song.id)
    }

    func toggleStar(_ song: Song) {
        guard let client else { return }
        let newValue = !starredSongIDs.contains(song.id)
        if newValue {
            starredSongIDs.insert(song.id)
        } else {
            starredSongIDs.remove(song.id)
        }
        Task {
            do {
                try await client.setStar(id: song.id, starred: newValue)
            } catch {
                // Roll back on failure.
                if newValue {
                    starredSongIDs.remove(song.id)
                } else {
                    starredSongIDs.insert(song.id)
                }
            }
        }
    }
}
