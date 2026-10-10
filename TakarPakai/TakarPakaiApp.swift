import SwiftUI
import Charts
import ServiceManagement
import AppKit

@main
struct TakarPakaiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var tokenService = TokenService()
    @StateObject private var launchAtLogin = LaunchAtLoginManager()

    var body: some Scene {
        WindowGroup("Takar Pakai", id: "main") {
            MainWindowView()
                .environmentObject(tokenService)
                .environmentObject(launchAtLogin)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(tokenService)
                .environmentObject(launchAtLogin)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                Text(tokenService.todayTokensFormatted)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(tokenService)
                .environmentObject(launchAtLogin)
        }
    }
}

/// Keeps the app behaving like a normal macOS application while the menu bar
/// extra continues monitoring after the main window is closed.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.title == "Takar Pakai" }) {
            window.makeKeyAndOrderFront(nil)
        }

        return true
    }
}
