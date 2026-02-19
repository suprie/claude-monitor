import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var tokenService: TokenService
    @EnvironmentObject var launchAtLogin: LaunchAtLoginManager

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin.isEnabled)
            }

            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Data Source", value: "~/.claude/projects")
            }

            Section("Statistics") {
                LabeledContent("Last Updated") {
                    if let lastUpdated = tokenService.lastUpdated {
                        Text(lastUpdated, style: .date)
                        Text(lastUpdated, style: .time)
                    } else {
                        Text("Never")
                    }
                }

                Button("Refresh Now") {
                    Task {
                        await tokenService.refresh()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 250)
    }
}

#Preview {
    SettingsView()
        .environmentObject(TokenService())
        .environmentObject(LaunchAtLoginManager())
}
