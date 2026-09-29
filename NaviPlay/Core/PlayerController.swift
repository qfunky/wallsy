import Foundation
import AVFoundation
import MediaPlayer
import AppKit

enum RepeatMode: String, Codable {
    case off, all, one

    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var queue: [Song] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var shuffleEnabled = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.8 {
        didSet {
            UserDefaults.standard.set(volume, forKey: "playerVolume")
            if !crossfading {
                activePlayer.volume = Float(volume)
            }
        }
    }
    /// Crossfade length in seconds; 0 disables it. Persisted.
    @Published var crossfadeDuration: Double {
        didSet { UserDefaults.standard.set(crossfadeDuration, forKey: "crossfadeDuration") }
    }

    var client: SubsonicClient?
    weak var downloads: DownloadManager?

    var currentSong: Song? {
        guard let index = currentIndex, queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    // MARK: - Internals

    private let players = [AVPlayer(), AVPlayer()]
    private var activeIdx = 0
    private var activePlayer: AVPlayer { players[activeIdx] }

    private var timeObservers: [Any] = []
    private var endObserver: NSObjectProtocol?
    private var originalQueue: [Song] = []
    private var scrobbleSubmitted = false

    private var crossfading = false
    private var fadeOutIdx: Int?
    private var fadeTimer: Timer?
    private let sessionKey = "savedPlaybackSession"
    private let positionKey = "savedPlaybackPosition"
    private var lastSavedSecond = -1
    private var restoringPosition: Double?

    private struct PlaybackSession: Codable {
        let server: String
        let username: String
        let queue: [Song]
        let originalQueue: [Song]
        let currentIndex: Int
        let position: Double
        let shuffle: Bool
        let repeatMode: RepeatMode
    }

    init() {
        let stored = UserDefaults.standard.object(forKey: "crossfadeDuration") as? Double
        crossfadeDuration = stored ?? 4
        volume = UserDefaults.standard.object(forKey: "playerVolume") as? Double ?? 0.8
        for p in players {
            p.volume = Float(volume)
        }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        for p in players {
            let observer = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak p] time in
                Task { @MainActor [weak self] in
                    guard let self, let p, p === self.activePlayer else { return }
                    self.tick(time)
                }
            }
            timeObservers.append(observer)
        }
        setupRemoteCommands()
    }

    deinit {
        for (i, observer) in timeObservers.enumerated() where i < players.count {
            players[i].removeTimeObserver(observer)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        fadeTimer?.invalidate()
    }

    // MARK: - Public API

    /// Restore the last queue for this account, paused at its saved position.
    func restoreSessionIfAvailable() {
        guard queue.isEmpty, let client,
              let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(PlaybackSession.self, from: data),
              session.server == client.config.baseURL.absoluteString,
              session.username == client.config.username,
              session.queue.indices.contains(session.currentIndex) else { return }
        queue = session.queue
        originalQueue = session.originalQueue
        currentIndex = session.currentIndex
        shuffleEnabled = session.shuffle
        repeatMode = session.repeatMode
        let position = UserDefaults.standard.object(forKey: positionKey) as? Double ?? session.position
        startPlayback(autoplay: false, at: position)
    }

    private func persistSession() {
        guard let client, let index = currentIndex, queue.indices.contains(index) else { return }
        let session = PlaybackSession(
            server: client.config.baseURL.absoluteString,
            username: client.config.username,
            queue: queue,
            originalQueue: originalQueue,
            currentIndex: index,
            position: currentTime,
            shuffle: shuffleEnabled,
            repeatMode: repeatMode
        )
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
        persistPosition()
    }

    private func persistPosition() {
        UserDefaults.standard.set(currentTime, forKey: positionKey)
    }

    func play(_ songs: [Song], startAt index: Int = 0) {
        guard !songs.isEmpty, songs.indices.contains(index) else { return }
        originalQueue = songs
        if shuffleEnabled {
            var rest = songs
            let first = rest.remove(at: index)
            queue = [first] + rest.shuffled()
            currentIndex = 0
        } else {
            queue = songs
            currentIndex = index
        }
        startPlayback()
    }

    func playNext(_ song: Song) {
        if queue.isEmpty {
            play([song])
        } else {
            let insertAt = (currentIndex ?? -1) + 1
            queue.insert(song, at: min(insertAt, queue.count))
            persistSession()
        }
    }

    func addToQueue(_ song: Song) {
        if queue.isEmpty {
            play([song])
        } else {
            queue.append(song)
            persistSession()
        }
    }

    func jump(to index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        startPlayback()
    }

    func togglePlayPause() {
        guard activePlayer.currentItem != nil else { return }
        if isPlaying {
            activePlayer.pause()
        } else {
            activePlayer.play()
        }
        isPlaying.toggle()
        updateNowPlayingPlaybackState()
        persistSession()
    }

    /// Manual "next": always wraps around the queue.
    func next() {
        cancelCrossfade()
        guard let index = currentIndex, !queue.isEmpty else { return }
        currentIndex = (index + 1) % queue.count
        startPlayback()
    }

    /// Manual "previous": restarts after 3s, otherwise wraps around (first -> last).
    func previous() {
        cancelCrossfade()
        guard let index = currentIndex, !queue.isEmpty else { return }
        if currentTime > 3 {
            seek(to: 0)
        } else {
            currentIndex = (index - 1 + queue.count) % queue.count
            startPlayback()
        }
    }

    func seek(to seconds: Double) {
        cancelCrossfade()
        restoringPosition = nil
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        activePlayer.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = clamped
        updateNowPlayingPlaybackState()
        persistSession()
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        guard let current = currentSong else { return }
        if shuffleEnabled {
            var rest = queue
            rest.removeAll { $0.id == current.id }
            queue = [current] + rest.shuffled()
            currentIndex = 0
        } else {
            if !originalQueue.isEmpty {
                queue = originalQueue
            }
            currentIndex = queue.firstIndex { $0.id == current.id } ?? 0
        }
        persistSession()
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next
        persistSession()
    }

    func clearUpcoming() {
        guard let index = currentIndex else { return }
        queue = Array(queue.prefix(index + 1))
        originalQueue = queue
        persistSession()
    }

    func stopAndClear() {
        cancelCrossfade()
        for p in players {
            p.pause()
            p.replaceCurrentItem(with: nil)
        }
        removeEndObserver()
        queue = []
        originalQueue = []
        currentIndex = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        UserDefaults.standard.removeObject(forKey: sessionKey)
        UserDefaults.standard.removeObject(forKey: positionKey)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Playback internals

    private func playbackURL(for song: Song) -> URL? {
        if let local = downloads?.localURL(for: song) {
            return local
        }
        return client?.streamURL(id: song.id)
    }

    private func startPlayback(autoplay: Bool = true, at position: Double = 0) {
        cancelCrossfade()
        guard let song = currentSong, let url = playbackURL(for: song) else { return }

        removeEndObserver()
        let item = AVPlayerItem(url: url)
        addEndObserver(for: item)

        activePlayer.replaceCurrentItem(with: item)
        activePlayer.volume = Float(volume)
        restoringPosition = position > 0 ? position : nil
        if position > 0 {
            activePlayer.seek(to: CMTime(seconds: position, preferredTimescale: 600),
                              toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if autoplay { activePlayer.play() }
        isPlaying = autoplay
        currentTime = position
        duration = Double(song.duration ?? 0)
        scrobbleSubmitted = false
        if autoplay { client?.scrobble(id: song.id, submission: false) }
        updateNowPlayingInfo()
        persistSession()
    }

    private func addEndObserver(for item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.trackEnded()
            }
        }
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    /// The index that natural playback advances to (no wrap unless repeat-all).
    private func autoNextIndex() -> Int? {
        guard let index = currentIndex else { return nil }
        if index + 1 < queue.count { return index + 1 }
        return repeatMode == .all && !queue.isEmpty ? 0 : nil
    }

    private func trackEnded() {
        if crossfading { return } // the fade already moved on
        if let song = currentSong, !scrobbleSubmitted {
            client?.scrobble(id: song.id, submission: true)
            scrobbleSubmitted = true
        }
        if repeatMode == .one {
            startPlayback()
        } else if let nextIndex = autoNextIndex() {
            currentIndex = nextIndex
            startPlayback()
        } else {
            activePlayer.pause()
            isPlaying = false
            updateNowPlayingPlaybackState()
        }
    }

    private func tick(_ time: CMTime) {
        guard time.isNumeric else { return }
        if let target = restoringPosition {
            guard abs(time.seconds - target) < 2 else { return }
            restoringPosition = nil
        }
        currentTime = time.seconds
        let second = Int(currentTime)
        if second / 5 != lastSavedSecond / 5 {
            lastSavedSecond = second
            persistPosition()
        }

        if duration <= 0,
           let itemDuration = activePlayer.currentItem?.duration,
           itemDuration.isNumeric {
            duration = itemDuration.seconds
        }

        if !scrobbleSubmitted, duration > 0, currentTime > duration / 2, let song = currentSong {
            client?.scrobble(id: song.id, submission: true)
            scrobbleSubmitted = true
        }

        maybeStartCrossfade()
    }

    // MARK: - Crossfade

    private func maybeStartCrossfade() {
        guard crossfadeDuration >= 0.5,
              !crossfading,
              isPlaying,
              repeatMode != .one,
              duration > crossfadeDuration * 2,
              let nextIndex = autoNextIndex() else {
            return
        }
        let remaining = duration - currentTime
        if remaining <= crossfadeDuration, remaining > 0.2 {
            beginCrossfade(to: nextIndex, over: min(crossfadeDuration, remaining))
        }
    }

    private func beginCrossfade(to index: Int, over fadeLength: Double) {
        guard queue.indices.contains(index),
              let url = playbackURL(for: queue[index]) else {
            return
        }
        let song = queue[index]

        // Submit the outgoing track's scrobble if it hasn't happened yet.
        if let outgoing = currentSong, !scrobbleSubmitted {
            client?.scrobble(id: outgoing.id, submission: true)
        }

        let outIdx = activeIdx
        let inIdx = 1 - activeIdx
        let incoming = players[inIdx]

        removeEndObserver()
        let item = AVPlayerItem(url: url)
        incoming.replaceCurrentItem(with: item)
        incoming.volume = 0
        incoming.play()

        activeIdx = inIdx
        fadeOutIdx = outIdx
        crossfading = true
        currentIndex = index
        currentTime = 0
        duration = Double(song.duration ?? 0)
        scrobbleSubmitted = false
        addEndObserver(for: item)
        client?.scrobble(id: song.id, submission: false)
        updateNowPlayingInfo()

        runFade(out: players[outIdx], in: incoming, over: fadeLength)
    }

    private func runFade(out outgoing: AVPlayer, in incoming: AVPlayer, over length: Double) {
        fadeTimer?.invalidate()
        let step = 0.05
        var elapsed = 0.0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { [weak self] timer in
            elapsed += step
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                let fraction = min(elapsed / length, 1)
                incoming.volume = Float(self.volume * fraction)
                outgoing.volume = Float(self.volume * (1 - fraction))
                if fraction >= 1 {
                    timer.invalidate()
                    outgoing.pause()
                    outgoing.replaceCurrentItem(with: nil)
                    self.crossfading = false
                    self.fadeOutIdx = nil
                }
            }
        }
    }

    private func cancelCrossfade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        if let outIdx = fadeOutIdx {
            players[outIdx].pause()
            players[outIdx].replaceCurrentItem(with: nil)
        }
        fadeOutIdx = nil
        crossfading = false
        activePlayer.volume = Float(volume)
    }

    // MARK: - Now Playing / media keys

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isPlaying else { return }
                self.togglePlayPause()
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.togglePlayPause()
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.togglePlayPause()
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.next()
            }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.previous()
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = event.positionTime
            Task { @MainActor [weak self] in
                self?.seek(to: position)
            }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist ?? "",
            MPMediaItemPropertyAlbumTitle: song.album ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        loadArtwork(for: song)
    }

    private func updateNowPlayingPlaybackState() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    private func loadArtwork(for song: Song) {
        guard let client, let cover = song.coverArt else { return }
        let url = client.coverArtURL(id: cover, size: 600)
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else {
                return
            }
            await MainActor.run { [weak self] in
                guard let self, self.currentSong?.id == song.id else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }
}
