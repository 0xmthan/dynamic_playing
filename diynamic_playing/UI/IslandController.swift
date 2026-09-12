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
        NowPlayingMonitor.shared.onTrackChange = { [weak self] in self?.peek() }
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
        let matching: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .scrollWheel]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: matching, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }) {
            eventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: matching, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updateHover() }
            return event
        }) {
            eventMonitors.append(local)
        }

        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
    }

    private func updateHover() {
        let state = IslandState.shared
        guard let panel else { return }

        let stage = state.stage(for: NowPlayingMonitor.shared)
        guard stage != .hidden else {
            state.isHovered = false
            return
        }

        guard !state.isScrubbing else { return }

        var rect = state.pillRect(for: stage).offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
        if state.isHovered { rect = rect.insetBy(dx: -12, dy: -12) }

        let inside = rect.contains(NSEvent.mouseLocation)
        if inside != state.isHovered { state.isHovered = inside }
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
