import Foundation

public enum HelperRegistrationState: Equatable, Sendable { case unregistered, enabled, requiresApproval, unavailable }

@MainActor
public protocol UpdateHelperService {
    var state: HelperRegistrationState { get }
    func register() throws
    func unregister() async throws
}

/// Keeps update recovery durable without turning a declined permission into consent.
@MainActor
public struct HelperUpdateRecovery {
    private let service: UpdateHelperService
    private let defaults: UserDefaults
    private let key = "vital.fan.reenableAfterUpdate"

    public init(service: UpdateHelperService, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    public func prepare() async throws -> Bool {
        guard service.state == .enabled || service.state == .requiresApproval else { return false }
        let resume = service.state == .enabled
        try await service.unregister() // Abort the update if the old helper cannot be removed.
        defaults.set(resume, forKey: key)
        return resume
    }

    /// Returns true if macOS needs the user to approve again. Failed registrations remain retryable.
    public func restore() throws -> Bool {
        guard defaults.bool(forKey: key) else { return false }
        if service.state != .enabled && service.state != .requiresApproval {
            do { try service.register() }
            catch {
                // Service Management can throw EPERM while successfully entering requiresApproval.
                guard service.state == .enabled || service.state == .requiresApproval else { throw error }
            }
        }
        guard service.state == .enabled || service.state == .requiresApproval else {
            throw NSError(domain: "Vital.HelperUpdate", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "macOS did not register fan control."])
        }
        defaults.removeObject(forKey: key)
        return service.state == .requiresApproval
    }
}
