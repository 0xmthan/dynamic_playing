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

    func start() {
        buildPanel()
        NowPlayingMonitor.shared.onTrackChange = { [weak self] in
            IslandState.shared.resetArtworkZoom()
            self?.peek()
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
            MainActor.assumeIsolated { self?.updateHover() }
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
}
