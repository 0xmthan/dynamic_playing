import AppKit
import Observation
import SwiftUI

struct NotchMetrics: Equatable {
    var width: CGFloat
    var height: CGFloat
    var hasNotch: Bool

    static let synthetic = NotchMetrics(width: 190, height: 32, hasNotch: false)

    static func read(from screen: NSScreen) -> NotchMetrics {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              screen.safeAreaInsets.top > 0 else { return .synthetic }
        let width = screen.frame.width - left.width - right.width
        guard width > 60 else { return .synthetic }
        return NotchMetrics(width: width.rounded(), height: screen.safeAreaInsets.top.rounded(), hasNotch: true)
    }
}

enum IslandStage: Equatable {
    case hidden, compact, expanded, focused
}

@Observable
final class IslandState {
    static let shared = IslandState()

    var metrics: NotchMetrics = .synthetic
    var isHovered = false
    var isScrubbing = false
    var isPeeking = false
    var isArtworkFocused = false
    var artworkZoom: CGFloat = 1
    var artworkPan: CGSize = .zero

    var peekOnTrackChange: Bool {
        didSet { UserDefaults.standard.set(peekOnTrackChange, forKey: Self.peekKey) }
    }

    private static let peekKey = "peekOnTrackChange"

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Self.peekKey: true])
        peekOnTrackChange = defaults.bool(forKey: Self.peekKey)
    }

    func stage(for monitor: NowPlayingMonitor) -> IslandStage {
        guard monitor.isActive else { return .hidden }
        if TrackSwap.shared.isActive { return .expanded }
        guard isHovered || isScrubbing || isPeeking else { return .compact }
        return isArtworkFocused ? .focused : .expanded
    }

    var compactSize: CGSize {
        CGSize(width: metrics.width + 134, height: metrics.height + 13)
    }

    var expandedSize: CGSize {
        CGSize(width: max(430, metrics.width + 248), height: metrics.height + 152)
    }

    var artworkTopGap: CGFloat { 12 }
    var expandedArtworkSize: CGFloat { 78 }
    var expandedArtworkInset: CGFloat { 22 }
    var focusedArtworkInset: CGFloat { 36 }

    var focusedArtworkSize: CGFloat {
        expandedSize.width - 2 * focusedArtworkInset
    }

    var focusedSize: CGSize {
        CGSize(width: expandedSize.width,
               height: metrics.height + artworkTopGap + focusedArtworkSize + focusedArtworkInset)
    }

    var idleSize: CGSize {
        CGSize(width: metrics.width, height: metrics.height)
    }

    func pillSize(for stage: IslandStage) -> CGSize {
        switch stage {
        case .hidden: idleSize
        case .compact: compactSize
        case .expanded: expandedSize
        case .focused: focusedSize
        }
    }

    func shoulder(for stage: IslandStage) -> CGFloat {
        switch stage {
        case .hidden: 0
        case .compact: 9
        case .expanded: 13
        case .focused: 13
        }
    }

    func bottomRadius(for stage: IslandStage) -> CGFloat {
        switch stage {
        case .hidden: metrics.hasNotch ? 10 : 16
        case .compact: 19
        case .expanded: 30
        case .focused: 34
        }
    }

    var windowSize: CGSize {
        CGSize(width: focusedSize.width + 90, height: focusedSize.height + 70)
    }

    var maxArtworkZoom: CGFloat { 5 }

    func zoomArtwork(by factor: CGFloat) {
        artworkZoom = min(maxArtworkZoom, max(1, artworkZoom * factor))
        artworkPan = clampedArtworkPan(artworkPan)
    }

    func setArtworkZoom(_ value: CGFloat) {
        artworkZoom = min(maxArtworkZoom, max(1, value))
        artworkPan = clampedArtworkPan(artworkPan)
    }

    func panArtwork(to value: CGSize) {
        artworkPan = clampedArtworkPan(value)
    }

    func resetArtworkZoom() {
        guard artworkZoom != 1 || artworkPan != .zero else { return }
        artworkZoom = 1
        artworkPan = .zero
    }

    func clampedArtworkPan(_ value: CGSize) -> CGSize {
        let limit = max(0, focusedArtworkSize * (artworkZoom - 1) / 2)
        return CGSize(width: min(limit, max(-limit, value.width)),
                      height: min(limit, max(-limit, value.height)))
    }

    func artworkRect(for stage: IslandStage) -> CGRect {
        let size: CGFloat
        let inset: CGFloat
        switch stage {
        case .expanded:
            size = expandedArtworkSize
            inset = expandedArtworkInset
        case .focused:
            size = focusedArtworkSize
            inset = focusedArtworkInset
        default:
            return .zero
        }
        let pill = pillRect(for: stage)
        return CGRect(x: pill.minX + inset,
                      y: pill.maxY - metrics.height - artworkTopGap - size,
                      width: size,
                      height: size)
    }

    func pillRect(for stage: IslandStage) -> CGRect {
        guard stage != .hidden else { return .zero }
        let window = windowSize
        let pill = pillSize(for: stage)
        return CGRect(x: ((window.width - pill.width) / 2).rounded(),
                      y: window.height - pill.height,
                      width: pill.width,
                      height: pill.height)
    }
}
