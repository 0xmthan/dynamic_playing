import AppKit
import SwiftUI

@Observable
final class TrackSwap {
    static let shared = TrackSwap()

    enum Phase {
        case idle, present, exit, slide, settle
    }

    private(set) var phase: Phase = .idle
    private(set) var leavingTrack: Track?
    private(set) var leavingPosition: TimeInterval = 0
    private(set) var leaving: NSImage?
    private(set) var leavingAccent: RGB = .neutral
    private(set) var forward = true
    private(set) var quick = false

    private init() {}

    var fromID: String? { leavingTrack?.id }

    var isActive: Bool { phase != .idle }

    var isSwapping: Bool { phase == .exit || phase == .slide }

    var showsLeaving: Bool { phase == .present || phase == .exit }

    var leavingColor: Color { leavingAccent.color }

    var leavingProgress: Double {
        guard let duration = leavingTrack?.duration, duration > 0 else { return 0 }
        return min(1, max(0, leavingPosition / duration))
    }

    private var travel: CGFloat {
        let distance = IslandState.shared.expandedArtworkSize + 40
        return forward ? distance : -distance
    }

    private var leavingFraction: CGFloat {
        switch phase {
        case .present: 0
        case .exit: quick ? 1 : 0
        case .slide, .settle, .idle: 1
        }
    }

    private var arrivingFraction: CGFloat { showsLeaving ? 0 : 1 }

    private var leavingMoves: Bool { phase == .slide || (phase == .exit && quick) }

    var leavingOffset: CGFloat { -travel * leavingFraction }

    var arrivingOffset: CGFloat { travel * (1 - arrivingFraction) }

    var leavingOpacity: Double { 1 - leavingFraction }

    var arrivingOpacity: Double { arrivingFraction }

    var leavingSlide: Animation? {
        guard leavingMoves else { return nil }
        return quick ? .smooth(duration: 0.35) : .artworkSlide
    }

    var leavingFade: Animation? {
        guard leavingMoves else { return nil }
        return .easeIn(duration: quick ? 0.25 : 0.6)
    }

    var arrivingSlide: Animation? {
        guard phase == .slide else { return nil }
        return quick ? .smooth(duration: 0.4) : .artworkSlide
    }

    var arrivingFade: Animation? {
        guard phase == .slide else { return nil }
        return quick ? .easeOut(duration: 0.3) : .easeOut(duration: 0.7).delay(0.12)
    }

    var infoOpacity: Double { isSwapping ? 0 : 1 }

    var infoAnimation: Animation {
        if quick {
            return isSwapping ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.25)
        }
        return isSwapping ? .easeInOut(duration: 0.35) : .easeInOut(duration: 0.5).delay(0.15)
    }

    func begin(track: Track, position: TimeInterval, artwork: NSImage?, accent: RGB, forward: Bool, quick: Bool) {
        leavingTrack = track
        leavingPosition = position
        leaving = artwork
        leavingAccent = accent
        self.forward = forward
        self.quick = quick
        phase = .present
    }

    func retarget(track: Track, position: TimeInterval) {
        leavingTrack = track
        leavingPosition = position
    }

    func exit() {
        guard phase == .present else { return }
        phase = .exit
    }

    func slide() {
        guard phase == .exit else { return }
        phase = .slide
    }

    func settle() {
        guard phase != .idle else { return }
        phase = .settle
    }

    func finish() {
        phase = .idle
        leavingTrack = nil
        leaving = nil
    }
}

extension RGB {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    var strength: Double { min(1, saturation * 3) }
}
