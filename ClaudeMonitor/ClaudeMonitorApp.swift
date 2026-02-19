import SwiftUI
import Charts
import ServiceManagement

@main
struct ClaudeMonitorApp: App {
    @StateObject private var tokenService = TokenService()
    @StateObject private var launchAtLogin = LaunchAtLoginManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(tokenService)
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
