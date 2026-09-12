import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class IslandHostingView: NSHostingView<IslandView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let stage = IslandState.shared.stage(for: NowPlayingMonitor.shared)
        guard IslandState.shared.pillRect(for: stage).contains(point) else { return nil }
        return super.hitTest(point)
    }
}

final class IslandController {
    private var panel: IslandPanel?
    private var hoverTimer: Timer?
    private var eventMonitors: [Any] = []
    private var peekTask: Task<Void, Never>?
    private var swapTask: Task<Void, Never>?
    private var anticipatedTrackID: String?

    func start() {
        buildPanel()
        NowPlayingMonitor.shared.onTrackChange = { [weak self] change in
            self?.handleTrackChange(change)
        }
        NowPlayingMonitor.shared.onSkip = { [weak self] forward in
            self?.handleSkip(forward: forward)
        }
        NowPlayingMonitor.shared.start()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }

        startHoverTracking()
    }

    private func buildPanel() {
        let state = IslandState.shared
        state.metrics = NotchMetrics.read(from: targetScreen)

        let panel = IslandPanel(contentRect: CGRect(origin: .zero, size: state.windowSize),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered,
                                defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.acceptsMouseMovedEvents = true

        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let hosting = IslandHostingView(rootView: IslandView())
        hosting.frame = CGRect(origin: .zero, size: state.windowSize)
        panel.contentView = hosting

        self.panel = panel
        reposition()
        panel.orderFrontRegardless()
    }

    private var targetScreen: NSScreen {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func reposition() {
        guard let panel else { return }
        let screen = targetScreen
        let state = IslandState.shared
        state.metrics = NotchMetrics.read(from: screen)

        let size = state.windowSize
        let origin = CGPoint(x: (screen.frame.midX - size.width / 2).rounded(),
                             y: screen.frame.maxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.contentView?.frame = CGRect(origin: .zero, size: size)
    }

    private func startHoverTracking() {
        let matching: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .scrollWheel, .magnify]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: matching, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            eventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: matching, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            eventMonitors.append(local)
        }

        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateHover()
                self?.anticipateTrackEnd()
            }
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .magnify { applyMagnification(event.magnification) }
        updateHover()
    }

    private func applyMagnification(_ magnification: CGFloat) {
        let state = IslandState.shared
        guard magnification != 0, state.isArtworkFocused, let panel else { return }

        let rect = state.artworkRect(for: .focused).offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
        guard rect.contains(NSEvent.mouseLocation) else { return }

        state.zoomArtwork(by: 1 + magnification * 1.5)
    }

    private func updateHover() {
        let state = IslandState.shared
        guard let panel else { return }

        let stage = state.stage(for: NowPlayingMonitor.shared)
        guard stage != .hidden else {
            releaseHover()
            return
        }

        guard !state.isScrubbing else { return }

        let mouse = NSEvent.mouseLocation
        var rect = state.pillRect(for: stage).offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
        if state.isHovered { rect = rect.insetBy(dx: -12, dy: -12) }

        let inside = rect.contains(mouse)
        if inside != state.isHovered { state.isHovered = inside }

        guard inside else {
            releaseFocus()
            return
        }
        guard !TrackSwap.shared.isActive else { return }
        updateArtworkFocus(stage: stage, mouse: mouse, origin: panel.frame.origin)
        updateArtworkPan(mouse: mouse, origin: panel.frame.origin)
    }

    private func updateArtworkPan(mouse: NSPoint, origin: NSPoint) {
        let state = IslandState.shared
        guard state.isArtworkFocused, state.artworkZoom > 1 else { return }

        let rect = state.artworkRect(for: .focused).offsetBy(dx: origin.x, dy: origin.y)
        guard rect.width > 0, rect.height > 0 else { return }

        let across = min(1, max(0, (mouse.x - rect.minX) / rect.width))
        let up = min(1, max(0, (mouse.y - rect.minY) / rect.height))
        let limit = max(0, state.focusedArtworkSize * (state.artworkZoom - 1) / 2)

        state.panArtwork(to: CGSize(width: limit * (1 - 2 * across),
                                    height: limit * (2 * up - 1)))
    }

    private func releaseHover() {
        let state = IslandState.shared
        if state.isHovered { state.isHovered = false }
        releaseFocus()
    }

    private func releaseFocus() {
        let state = IslandState.shared
        if state.isArtworkFocused { state.isArtworkFocused = false }
        state.resetArtworkZoom()
    }

    private func updateArtworkFocus(stage: IslandStage, mouse: NSPoint, origin: NSPoint) {
        let state = IslandState.shared
        let artwork = state.artworkRect(for: stage).offsetBy(dx: origin.x, dy: origin.y)

        switch stage {
        case .expanded:
            if artwork.insetBy(dx: 12, dy: 12).contains(mouse) { state.isArtworkFocused = true }
        case .focused:
            if !artwork.insetBy(dx: -6, dy: -6).contains(mouse) { releaseFocus() }
        default:
            break
        }
    }

    private func peek() {
        let state = IslandState.shared
        guard state.peekOnTrackChange else { return }
        peekTask?.cancel()
        state.isPeeking = true
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled, self != nil else { return }
            state.isPeeking = false
        }
    }

    private func handleTrackChange(_ change: TrackChange) {
        let state = IslandState.shared
        let swap = TrackSwap.shared
        state.resetArtworkZoom()

        if swap.isActive, swap.fromID == change.previous?.id { return }
        guard let previous = change.previous, state.peekOnTrackChange || state.isHovered else {
            peek()
            return
        }
        let skipped = previous.duration - change.previousPosition > 3
        runSwap(leaving: previous,
                position: change.previousPosition,
                artwork: change.previousArtwork,
                accent: change.previousAccent,
                forward: true,
                presentFor: skipped ? nil : 1.4)
    }

    private func handleSkip(forward: Bool) {
        let monitor = NowPlayingMonitor.shared
        let state = IslandState.shared
        guard let track = monitor.track, state.peekOnTrackChange || state.isHovered else { return }
        runSwap(leaving: track,
                position: monitor.position,
                artwork: monitor.artwork,
                accent: monitor.accent,
                forward: forward,
                presentFor: nil)
    }

    private func anticipateTrackEnd() {
        let monitor = NowPlayingMonitor.shared
        let state = IslandState.shared
        guard monitor.state == .playing,
              let track = monitor.track,
              track.duration > 10,
              track.id != anticipatedTrackID,
              !TrackSwap.shared.isActive,
              !state.isScrubbing,
              state.peekOnTrackChange || state.isHovered else { return }

        let remaining = track.duration - monitor.position
        guard remaining > 0, remaining <= 2.2 else { return }

        anticipatedTrackID = track.id
        runSwap(leaving: track,
                position: monitor.position,
                artwork: monitor.artwork,
                accent: monitor.accent,
                forward: true,
                presentFor: 1.4,
                patience: remaining + 2.5)
    }

    private func runSwap(leaving track: Track,
                         position: TimeInterval,
                         artwork: NSImage?,
                         accent: RGB,
                         forward: Bool,
                         presentFor minimum: TimeInterval?,
                         patience: TimeInterval = 2) {
        let state = IslandState.shared
        let swap = TrackSwap.shared
        let monitor = NowPlayingMonitor.shared
        let quick = minimum == nil

        swapTask?.cancel()
        state.isArtworkFocused = false
        state.resetArtworkZoom()
        peek()

        let resumesExit = quick && swap.quick && swap.phase == .exit
        if resumesExit {
            swap.retarget(track: track, position: position)
        } else {
            swap.begin(track: track, position: position, artwork: artwork, accent: accent,
                       forward: forward, quick: quick)
        }

        swapTask = Task { [weak self] in
            if let minimum {
                await Self.wait(atLeast: minimum, atMost: patience) { monitor.track?.id != track.id }
                guard !Task.isCancelled else { return }
                guard monitor.track?.id != track.id else {
                    swap.finish()
                    self?.peek()
                    return
                }
                swap.exit()
            } else if !resumesExit {
                try? await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { return }
                swap.exit()
            }

            await Self.wait(atLeast: quick ? 0.12 : 0.5, atMost: quick ? 3 : 2) {
                monitor.track?.id != track.id && !monitor.isArtworkPending
            }
            guard !Task.isCancelled else { return }

            if monitor.track?.id != track.id {
                swap.slide()
                try? await Task.sleep(for: .milliseconds(quick ? 300 : 820))
                guard !Task.isCancelled else { return }
            }

            swap.settle()
            try? await Task.sleep(for: .milliseconds(quick ? 300 : 750))
            guard !Task.isCancelled else { return }

            swap.finish()
            self?.peek()
        }
    }

    private static func wait(atLeast minimum: TimeInterval,
                             atMost maximum: TimeInterval,
                             until ready: () -> Bool) async {
        let start = Date()
        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= maximum || (elapsed >= minimum && ready()) { return }
            try? await Task.sleep(for: .milliseconds(40))
        }
    }
}
