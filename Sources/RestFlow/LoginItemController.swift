import ServiceManagement
import RestFlowCore

@MainActor
protocol LoginItemManaging {
    var status: SMAppService.Status { get }
    func apply(enabled: Bool) throws
}

@MainActor
final class LoginItemController: LoginItemManaging {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func apply(enabled: Bool) throws {
        if enabled {
            if status != .enabled && status != .requiresApproval { try SMAppService.mainApp.register() }
        } else if status == .enabled || status == .requiresApproval {
            try SMAppService.mainApp.unregister()
        }
    }
}
