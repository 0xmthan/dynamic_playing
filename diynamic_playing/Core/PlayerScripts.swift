import Foundation

nonisolated enum PlayerScripts {
    static let separator = "\u{1F}"

    static func snapshot(for source: MediaSource) -> String {
        switch source {
        case .spotify: spotifySnapshot
        case .music: musicSnapshot
        }
    }

    private static let spotifySnapshot = """
    set sep to (character id 31)
    set out to "stopped"
    tell application id "com.spotify.client"
        set ps to (player state as text)
        if ps is not "stopped" then
            set t to current track
            set tid to ""
            try
                set tid to (id of t) as text
            end try
            set nm to ""
            try
                set nm to (name of t) as text
            end try
            set ar to ""
            try
                set ar to (artist of t) as text
            end try
            set al to ""
            try
                set al to (album of t) as text
            end try
            set du to 0
            try
                set du to (duration of t) as integer
            end try
            set po to 0
            try
                set po to (round ((player position) * 1000))
            end try
            set aw to ""
            try
                set aw to (artwork url of t) as text
            end try
            set out to ps & sep & tid & sep & nm & sep & ar & sep & al & sep & (du as text) & sep & (po as text) & sep & aw
        end if
    end tell
    return out
    """

    private static let musicSnapshot = """
    set sep to (character id 31)
    set out to "stopped"
    tell application id "com.apple.Music"
        set ps to (player state as text)
        if ps is not "stopped" then
            set t to current track
            set tid to ""
            try
                set tid to (persistent ID of t) as text
            end try
            if tid is "" then
                try
                    set tid to (database ID of t) as text
                end try
            end if
            set nm to ""
            try
                set nm to (name of t) as text
            end try
            set ar to ""
            try
                set ar to (artist of t) as text
            end try
            set al to ""
            try
                set al to (album of t) as text
            end try
            set du to 0
            try
                set du to (round ((duration of t) * 1000))
            end try
            set po to 0
            try
                set po to (round ((player position) * 1000))
            end try
            set out to ps & sep & tid & sep & nm & sep & ar & sep & al & sep & (du as text) & sep & (po as text) & sep & ""
        end if
    end tell
    return out
    """

    static let musicArtwork = """
    tell application id "com.apple.Music"
        try
            set t to current track
            if (count of artworks of t) is 0 then return ""
            return (raw data of artwork 1 of t)
        on error
            return ""
        end try
    end tell
    """

    static func playPause(_ source: MediaSource) -> String {
        "tell application id \"\(source.bundleID)\" to playpause"
    }

    static func nextTrack(_ source: MediaSource) -> String {
        "tell application id \"\(source.bundleID)\" to next track"
    }

    static func previousTrack(_ source: MediaSource) -> String {
        switch source {
        case .spotify:
            return "tell application id \"com.spotify.client\" to previous track"
        case .music:
            return """
            tell application id "com.apple.Music"
                if player position > 3 then
                    set player position to 0
                else
                    previous track
                end if
            end tell
            """
        }
    }

    static func seek(_ source: MediaSource, to seconds: TimeInterval) -> String {
        let value = String(format: "%.3f", max(0, seconds))
        return "tell application id \"\(source.bundleID)\" to set player position to \(value)"
    }
}
