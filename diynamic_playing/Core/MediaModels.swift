import Foundation

nonisolated enum PlayerState: String {
    case playing, paused, stopped

    init(appleScriptValue: String) {
        switch appleScriptValue.lowercased() {
        case "playing", "fast forwarding", "rewinding": self = .playing
        case "paused": self = .paused
        default: self = .stopped
        }
    }
}

nonisolated enum MediaSource: String, CaseIterable, Identifiable {
    case spotify, music

    var id: String { rawValue }

    var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        }
    }

    var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Music"
        }
    }

    var glyph: String {
        switch self {
        case .spotify: "waveform.circle.fill"
        case .music: "music.note"
        }
    }
}

nonisolated struct Track: Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var artworkURL: URL?

    var isEmpty: Bool { title.isEmpty && artist.isEmpty }
}

nonisolated struct Snapshot: Equatable {
    var source: MediaSource
    var state: PlayerState
    var track: Track
    var position: TimeInterval
}
