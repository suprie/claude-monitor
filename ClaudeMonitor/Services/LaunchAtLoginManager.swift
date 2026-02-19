import Foundation
import ServiceManagement

@MainActor
class LaunchAtLoginManager: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            if isEnabled {
                enable()
            } else {
                disable()
            }
        }
    }

    init() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }

    private func enable() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            print("Failed to enable launch at login: \(error)")
            isEnabled = false
        }
    }

    private func disable() {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            print("Failed to disable launch at login: \(error)")
            isEnabled = true
        }
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
