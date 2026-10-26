import ServiceManagement

/// Injectable boundary over `SMAppService.mainApp`'s login-item operations.
///
/// `Preferences` talks to the real service through `.system`; tests substitute
/// stateful closures so registration never touches the actual login item.
struct LoginItemService {
    let status: () -> SMAppService.Status
    let register: () throws -> Void
    let unregister: () throws -> Void
    static let system = LoginItemService(status: { SMAppService.mainApp.status },
        register: { try SMAppService.mainApp.register() },
        unregister: { try SMAppService.mainApp.unregister() })
}
