import SwiftUI

extension Animation {
    static let island = Animation.spring(response: 0.42, dampingFraction: 0.78)
}

struct IslandView: View {
    private let monitor = NowPlayingMonitor.shared
    private let state = IslandState.shared

    var body: some View {
        let stage = state.stage(for: monitor)
        let size = state.pillSize(for: stage)
        let shoulder = state.shoulder(for: stage)
        let radius = state.bottomRadius(for: stage)
        let shape = NotchShape(shoulder: shoulder, bottomRadius: radius)

        ZStack(alignment: .top) {
            compactLayout(stage: stage)
                .frame(width: state.compactSize.width, height: state.compactSize.height)
                .opacity(stage == .compact ? 1 : 0)

            expandedLayout(stage: stage)
                .frame(width: state.expandedSize.width, height: state.expandedSize.height)
                .opacity(stage == .expanded ? 1 : 0)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background {
            shape.fill(.black)
            shape.fill(
                LinearGradient(colors: [monitor.accentColor.opacity(0.16 * monitor.accentStrength), .clear],
                               startPoint: .top, endPoint: .bottom)
            )
            shape.stroke(.white.opacity(0.09), lineWidth: 0.6)
        }
        .clipShape(shape)
        .compositingGroup()
        .shadow(color: .black.opacity(stage == .expanded ? 0.55 : 0.3),
                radius: stage == .expanded ? 22 : 8, y: stage == .expanded ? 10 : 4)
        .opacity(stage == .hidden ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.island, value: stage)
        .animation(.easeInOut(duration: 0.35), value: monitor.accent)
        .environment(\.colorScheme, .dark)
    }

    private func compactLayout(stage: IslandStage) -> some View {
        let badge = state.compactSize.height - 15

        return HStack(spacing: 0) {
            ArtworkView(image: monitor.artwork,
                        accent: monitor.accentColor,
                        size: badge,
                        corner: 7)

            Spacer(minLength: state.metrics.width)

            TimelineView(.animation(minimumInterval: 0.5, paused: stage != .compact)) { _ in
                ProgressRing(progress: monitor.progress,
                             accent: monitor.accentColor,
                             diameter: badge,
                             lineWidth: 2.2) {
                    if monitor.state == .playing {
                        Visualizer(isPlaying: true,
                                   color: monitor.accentColor,
                                   height: badge * 0.42,
                                   barWidth: 2)
                    } else {
                        Image(systemName: "pause.fill")
                            .font(.system(size: badge * 0.34, weight: .bold))
                            .foregroundStyle(monitor.accentColor)
                    }
                }
            }
        }
        .padding(.horizontal, state.shoulder(for: .compact) + 12)
    }

    private func expandedLayout(stage: IslandStage) -> some View {
        VStack(spacing: 0) {
            header
                .frame(height: state.metrics.height)

            HStack(alignment: .top, spacing: 14) {
                ArtworkView(image: monitor.artwork,
                            accent: monitor.accentColor,
                            size: 78,
                            corner: 13)
                    .onTapGesture { monitor.activateSourceApp() }

                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.track?.title ?? "")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(monitor.track?.artist ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                    Text(monitor.track?.album ?? "")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.32))
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    scrubber(stage: stage)
                }
                .frame(height: 78)
            }
            .padding(.top, 12)

            controls
                .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: monitor.source?.glyph ?? "music.note")
                    .font(.system(size: 10, weight: .semibold))
                Text(monitor.source?.displayName.uppercased() ?? "")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
            }
            .foregroundStyle(monitor.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer().frame(width: state.metrics.width)

            HStack(spacing: 7) {
                Text(monitor.state == .playing ? "NOW PLAYING" : "PAUSED")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.42))
                Visualizer(isPlaying: monitor.state == .playing,
                           color: monitor.accentColor,
                           height: 11,
                           barWidth: 2)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func scrubber(stage: IslandStage) -> some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: stage != .expanded)) { _ in
            ScrubBar(progress: monitor.progress,
                     accent: monitor.accentColor,
                     elapsed: Self.time(monitor.position),
                     remaining: "-" + Self.time(max(0, (monitor.track?.duration ?? 0) - monitor.position)),
                     onScrubbingChanged: { state.isScrubbing = $0 },
                     onSeek: { monitor.seek(toFraction: $0) })
        }
    }

    private var controls: some View {
        HStack(spacing: 24) {
            ControlButton(symbol: "backward.fill", size: 14, accent: monitor.accentColor) {
                monitor.previousTrack()
            }
            ControlButton(symbol: monitor.state == .playing ? "pause.fill" : "play.fill",
                          size: 17,
                          accent: monitor.accentColor,
                          prominent: true) {
                monitor.togglePlayPause()
            }
            ControlButton(symbol: "forward.fill", size: 14, accent: monitor.accentColor) {
                monitor.nextTrack()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private static func time(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0:00" }
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

struct ScrubBar: View {
    var progress: Double
    var accent: Color
    var elapsed: String
    var remaining: String
    var onScrubbingChanged: (Bool) -> Void
    var onSeek: (Double) -> Void

    @State private var dragFraction: Double?

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                let fraction = dragFraction ?? progress
                let width = max(geometry.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule()
                        .fill(LinearGradient(colors: [accent.opacity(0.75), accent],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, width * fraction))
                }
                .frame(height: dragFraction == nil ? 4 : 6)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragFraction == nil { onScrubbingChanged(true) }
                            dragFraction = clamp(value.location.x / width)
                        }
                        .onEnded { value in
                            let target = clamp(value.location.x / width)
                            dragFraction = nil
                            onScrubbingChanged(false)
                            onSeek(target)
                        }
                )
                .animation(.easeOut(duration: 0.15), value: dragFraction == nil)
            }
            .frame(height: 10)

            HStack {
                Text(elapsed)
                Spacer()
                Text(remaining)
            }
            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}

struct ControlButton: View {
    var symbol: String
    var size: CGFloat
    var accent: Color
    var prominent: Bool = false
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(prominent ? .white : Color.white.opacity(isHovered ? 1 : 0.72))
                .frame(width: prominent ? 34 : 28, height: prominent ? 34 : 28)
                .background {
                    if prominent {
                        Circle().fill(accent.opacity(isHovered ? 0.32 : 0.2))
                    } else if isHovered {
                        Circle().fill(.white.opacity(0.1))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.08 : 1)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
