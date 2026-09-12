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
    case hidden, compact, expanded
}

@Observable
final class IslandState {
    static let shared = IslandState()

    var metrics: NotchMetrics = .synthetic
    var isHovered = false
    var isScrubbing = false
    var isPeeking = false

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
        if isHovered || isScrubbing || isPeeking { return .expanded }
        return .compact
    }

    var compactSize: CGSize {
        CGSize(width: metrics.width + 134, height: metrics.height + 13)
    }

    var expandedSize: CGSize {
        CGSize(width: max(430, metrics.width + 248), height: metrics.height + 152)
    }

    var idleSize: CGSize {
        CGSize(width: metrics.width, height: metrics.height)
    }

    func pillSize(for stage: IslandStage) -> CGSize {
        switch stage {
        case .hidden: idleSize
        case .compact: compactSize
        case .expanded: expandedSize
        }
    }

    func shoulder(for stage: IslandStage) -> CGFloat {
        switch stage {
        case .hidden: 0
        case .compact: 9
        case .expanded: 13
        }
    }

    func bottomRadius(for stage: IslandStage) -> CGFloat {
        switch stage {
        case .hidden: metrics.hasNotch ? 10 : 16
        case .compact: 19
        case .expanded: 30
        }
    }

    var windowSize: CGSize {
        CGSize(width: expandedSize.width + 90, height: expandedSize.height + 70)
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
