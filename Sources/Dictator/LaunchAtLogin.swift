import AppKit
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> SMAppService.Status {
        if enabled {
            if SMAppService.mainApp.status == .enabled {
                return .enabled
            }
            try SMAppService.mainApp.register()
        } else {
            if SMAppService.mainApp.status == .notRegistered {
                return .notRegistered
            }
            try SMAppService.mainApp.unregister()
        }
        return SMAppService.mainApp.status
    }

    static func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
