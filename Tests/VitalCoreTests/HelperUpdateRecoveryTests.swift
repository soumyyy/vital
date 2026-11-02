import Foundation
import Testing
@testable import VitalCore

@MainActor
private final class UpdateService: UpdateHelperService {
    var state = HelperRegistrationState.enabled
    var registrationState = HelperRegistrationState.enabled
    var failRegister = false
    var failUnregister = false
    var registrations = 0
    func register() throws {
        registrations += 1
        if failRegister { throw NSError(domain: "test", code: 1) }
        state = registrationState
    }
    func unregister() async throws {
        if failUnregister { throw NSError(domain: "test", code: 2) }
        state = .unregistered
    }
}

@MainActor
private func fixture() -> (UpdateService, UserDefaults, HelperUpdateRecovery) {
    let service = UpdateService()
    let defaults = UserDefaults(suiteName: "test.vital.helper.\(UUID())")!
    return (service, defaults, HelperUpdateRecovery(service: service, defaults: defaults))
}

@Test @MainActor func updateRestoresOnlyPreviouslyEnabledFanControl() async throws {
    let (service, defaults, recovery) = fixture()
    #expect(try await recovery.prepare())
    #expect(service.state == .unregistered)
    // A new coordinator models the restarted app, using the durable recovery marker.
    let restarted = HelperUpdateRecovery(service: service, defaults: defaults)
    #expect(try restarted.restore() == false)
    #expect(service.state == .enabled)
    #expect(try restarted.restore() == false)
    #expect(service.registrations == 1)
}

@Test @MainActor func updateDoesNotTurnDeclinedApprovalIntoConsent() async throws {
    let (service, _, recovery) = fixture()
    service.state = .requiresApproval
    #expect(try await recovery.prepare() == false)
    #expect(try recovery.restore() == false)
    #expect(service.registrations == 0)
}

@Test @MainActor func failedHelperRemovalAbortsPreparation() async throws {
    let (service, _, recovery) = fixture()
    service.failUnregister = true
    do { _ = try await recovery.prepare(); Issue.record("should fail") } catch {}
    #expect(service.state == .enabled)
    #expect(try recovery.restore() == false)
    #expect(service.registrations == 0)
}

@Test @MainActor func registrationFailureRetainsTheRecoveryMarker() async throws {
    let (service, _, recovery) = fixture()
    _ = try await recovery.prepare()
    service.failRegister = true
    #expect(throws: NSError.self) { try recovery.restore() }
    service.failRegister = false
    #expect(try recovery.restore() == false)
    #expect(service.state == .enabled)
    #expect(service.registrations == 2)
}

@Test @MainActor func restoredHelperReportsApprovalRequired() async throws {
    let (service, _, recovery) = fixture()
    _ = try await recovery.prepare()
    service.registrationState = .requiresApproval
    #expect(try recovery.restore())
    #expect(service.state == .requiresApproval)
}

@Test @MainActor func neverEnabledHelperStaysOffDuringAnUpdate() async throws {
    let (service, _, recovery) = fixture()
    service.state = .unregistered
    #expect(try await recovery.prepare() == false)
    #expect(try recovery.restore() == false)
    #expect(service.registrations == 0)
}
