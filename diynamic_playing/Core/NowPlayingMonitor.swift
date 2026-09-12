import AppKit
import Observation
import SwiftUI

struct TrackChange {
    var previous: Track?
    var previousPosition: TimeInterval
    var previousArtwork: NSImage?
    var previousAccent: RGB
}

@Observable
final class NowPlayingMonitor {
    static let shared = NowPlayingMonitor()

    private(set) var source: MediaSource?
    private(set) var state: PlayerState = .stopped
    private(set) var track: Track?
    private(set) var artwork: NSImage?
    private(set) var accent: RGB = .neutral

    private(set) var automationDenied = false
    private(set) var isArtworkPending = false

    var onTrackChange: ((TrackChange) -> Void)?
    var onSkip: ((Bool) -> Void)?

    private var positionSample: TimeInterval = 0
    private var sampleDate: Date = .distantPast
    private var lastPlayingSource: MediaSource?
    private var artworkKey: String?
    private var pollTask: Task<Void, Never>?
    private var pendingRefresh: Task<Void, Never>?

    private init() {}

    var isActive: Bool { track != nil && state != .stopped }

    var position: TimeInterval {
        guard let track else { return 0 }
        guard state == .playing else { return min(positionSample, track.duration) }
        let elapsed = Date().timeIntervalSince(sampleDate)
        return min(track.duration, positionSample + max(0, elapsed))
    }

    var progress: Double {
        guard let track, track.duration > 0 else { return 0 }
        return min(1, max(0, position / track.duration))
    }

    var accentColor: Color {
        Color(.sRGB, red: accent.red, green: accent.green, blue: accent.blue)
    }

    var accentStrength: Double {
        min(1, accent.saturation * 3)
    }

    func start() {
        observePlayerNotifications()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    private var pollInterval: Double {
        switch state {
        case .playing: 1.0
        case .paused: 2.5
        case .stopped: 4.0
        }
    }

    private func observePlayerNotifications() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSoon() }
            }
        }
    }

    func refreshSoon(after delay: Duration = .milliseconds(120)) {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["DIYNAMIC_DEMO"] == "1" {
            applyDemoSnapshot()
            return
        }
        #endif

        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let candidates = MediaSource.allCases.filter { running.contains($0.bundleID) }
        guard !candidates.isEmpty else {
            clear()
            return
        }

        var snapshots: [Snapshot] = []
        var deniedCount = 0
        for candidate in candidates {
            switch await AppleScriptBridge.text(PlayerScripts.snapshot(for: candidate)) {
            case .success(let raw):
                if let snapshot = parse(raw, from: candidate) { snapshots.append(snapshot) }
            case .failure(let error):
                if error.isAuthorizationFailure { deniedCount += 1 }
            }
        }

        automationDenied = deniedCount == candidates.count && deniedCount > 0

        guard let chosen = pick(from: snapshots) else {
            clear()
            return
        }
        apply(chosen)
    }

    private func pick(from snapshots: [Snapshot]) -> Snapshot? {
        let playing = snapshots.filter { $0.state == .playing }
        if !playing.isEmpty {
            return playing.first { $0.source == lastPlayingSource } ?? playing.first
        }
        let paused = snapshots.filter { $0.state == .paused }
        return paused.first { $0.source == lastPlayingSource } ?? paused.first
    }

    private func parse(_ raw: String, from source: MediaSource) -> Snapshot? {
        let fields = raw.components(separatedBy: PlayerScripts.separator)
        guard fields.count >= 7 else { return nil }
        let state = PlayerState(appleScriptValue: fields[0])
        guard state != .stopped else { return nil }

        let durationMS = Double(fields[5]) ?? 0
        let positionMS = Double(fields[6]) ?? 0
        let artworkURL = fields.count > 7 ? URL(string: fields[7]) : nil

        let track = Track(id: fields[1].isEmpty ? fields[2] + fields[3] : fields[1],
                          title: fields[2],
                          artist: fields[3],
                          album: fields[4],
                          duration: durationMS / 1000,
                          artworkURL: artworkURL)
        guard !track.isEmpty else { return nil }

        return Snapshot(source: source, state: state, track: track, position: positionMS / 1000)
    }

    private func apply(_ snapshot: Snapshot) {
        let previous = track
        let previousPosition = position
        let previousArtwork = artwork
        let previousAccent = accent
        let changedTrack = previous?.id != snapshot.track.id

        source = snapshot.source
        state = snapshot.state
        track = snapshot.track
        positionSample = snapshot.position
        sampleDate = Date()
        if snapshot.state == .playing { lastPlayingSource = snapshot.source }

        if changedTrack {
            loadArtwork(for: snapshot)
            onTrackChange?(TrackChange(previous: previous,
                                       previousPosition: previousPosition,
                                       previousArtwork: previousArtwork,
                                       previousAccent: previousAccent))
        } else if artworkKey != key(for: snapshot) {
            loadArtwork(for: snapshot)
        }
    }

    private func clear() {
        guard track != nil || state != .stopped else { return }
        source = nil
        state = .stopped
        track = nil
        artwork = nil
        accent = .neutral
        artworkKey = nil
        isArtworkPending = false
    }

    private func key(for snapshot: Snapshot) -> String {
        "\(snapshot.source.rawValue):\(snapshot.track.id)"
    }

    private func loadArtwork(for snapshot: Snapshot) {
        let newKey = key(for: snapshot)
        artworkKey = newKey
        isArtworkPending = true
        Task { [weak self] in
            let data = await Artwork.load(source: snapshot.source, track: snapshot.track)
            guard let self, self.artworkKey == newKey else { return }
            guard let data, let image = NSImage(data: data) else {
                self.artwork = nil
                self.accent = .neutral
                self.isArtworkPending = false
                return
            }
            let accent = await Task.detached(priority: .utility) { Artwork.accent(from: data) }.value
            guard self.artworkKey == newKey else { return }
            self.artwork = image
            self.accent = accent
            self.isArtworkPending = false
        }
    }

    func togglePlayPause() {
        guard let source else { return }
        AppleScriptBridge.fire(PlayerScripts.playPause(source))
        refreshSoon(after: .milliseconds(220))
    }

    func nextTrack() {
        guard let source else { return }
        onSkip?(true)
        AppleScriptBridge.fire(PlayerScripts.nextTrack(source))
        refreshSoon(after: .milliseconds(320))
    }

    func previousTrack() {
        guard let source else { return }
        onSkip?(false)
        AppleScriptBridge.fire(PlayerScripts.previousTrack(source))
        refreshSoon(after: .milliseconds(320))
    }

    func seek(toFraction fraction: Double) {
        guard let source, let track, track.duration > 0 else { return }
        let seconds = min(track.duration, max(0, fraction * track.duration))

        positionSample = seconds
        sampleDate = Date()
        AppleScriptBridge.fire(PlayerScripts.seek(source, to: seconds))
        refreshSoon(after: .milliseconds(400))
    }

    func activateSourceApp() {
        guard let source,
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == source.bundleID })
        else { return }
        app.activate(options: [])
    }

    #if DEBUG
    private func applyDemoSnapshot() {
        guard track == nil else {
            positionSample = position
            sampleDate = Date()
            return
        }
        let demo = Track(id: "demo", title: "Midnight Arcade", artist: "Neon Corridor",
                         album: "Afterglow", duration: 227, artworkURL: nil)
        source = .spotify
        state = .playing
        track = demo
        positionSample = 71
        sampleDate = Date()
        accent = RGB(red: 0.44, green: 0.72, blue: 1.0)
        artwork = Self.demoArtwork()
    }

    private static func demoArtwork() -> NSImage {
        let size = NSSize(width: 300, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.16, green: 0.28, blue: 0.72, alpha: 1),
            NSColor(srgbRed: 0.85, green: 0.32, blue: 0.55, alpha: 1)
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 45)
        image.unlockFocus()
        return image
    }
    #endif
}
