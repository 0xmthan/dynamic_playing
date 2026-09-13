import AppKit
import SwiftUI

@main
struct dynamic_playingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(systemName: "waveform")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let island = IslandController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        island.start()
    }
}

struct MenuBarContent: View {
    private let monitor = NowPlayingMonitor.shared
    @Bindable private var state = IslandState.shared

    var body: some View {
        if let track = monitor.track {
            Text(track.title)
            Text(track.artist)
            Button("Open \(monitor.source?.displayName ?? "Player")") {
                monitor.activateSourceApp()
            }
        } else if monitor.automationDenied {
            Text("Automation access is turned off")
            Button("Open Privacy Settings…") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
                NSWorkspace.shared.open(url)
            }
        } else {
            Text("Nothing playing")
        }

        Divider()

        Toggle("Peek on track change", isOn: $state.peekOnTrackChange)

        Divider()

        Button("Quit dynamic playing") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
