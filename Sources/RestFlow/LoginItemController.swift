import ServiceManagement
import RestFlowCore

@MainActor
final class LoginItemController {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func apply(enabled: Bool) throws {
        if enabled {
            if status != .enabled && status != .requiresApproval { try SMAppService.mainApp.register() }
        } else if status == .enabled || status == .requiresApproval {
            try SMAppService.mainApp.unregister()
        }
    }
}
