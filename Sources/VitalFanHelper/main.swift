import Foundation
import MachO
import IOKit.pwr_mgt
import CVitalSensors
import VitalCore
import VitalFanIPC

final class Helper: NSObject, NSXPCListenerDelegate {
    let queue = DispatchQueue(label: "dev.soumya.vital.fans.hardware")
    let session = FanSession()
    private var owner: NSXPCConnection?
    private var timer: DispatchSourceTimer?
    let requirement: String
    init(requirement: String) {
        self.requirement = requirement
        super.init()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in self?.session.tick() }
        timer.resume(); self.timer = timer
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(requirement)
        return queue.sync {
            guard owner == nil else { return false }
            owner = connection
            connection.exportedInterface = NSXPCInterface(with: FanServiceProtocol.self)
            connection.exportedObject = Endpoint(helper: self)
            connection.invalidationHandler = { [weak self, weak connection] in
                guard let self else { return }
                self.queue.async {
                    if self.owner === connection { self.session.reset(); self.owner = nil }
                }
            }
            connection.interruptionHandler = { [weak connection] in connection?.invalidate() }
            connection.resume()
            return true
        }
    }
}

final class Endpoint: NSObject, FanServiceProtocol {
    unowned let helper: Helper
    init(helper: Helper) { self.helper = helper }
    func set(fan: Int, rpm: Double, reply: @escaping (String?) -> Void) {
        helper.queue.async { [self] in
            do { try helper.session.set(fan: fan, rpm: rpm); reply(nil) }
            catch { reply(error.localizedDescription) }
        }
    }
    func status(reply: @escaping ([String: NSNumber], String?) -> Void) {
        helper.queue.async { [self] in
            helper.session.tick(); helper.session.renew()
            reply(Dictionary(uniqueKeysWithValues: helper.session.targets.map { (String($0.key), NSNumber(value: $0.value)) }), helper.session.resetError)
        }
    }
}

// The helper is embedded beside Vital, so both peers can pin the exact bundled code signature.
// launchd can supply a relative argv[0]; resolve the running image, not its argument string.
var executableSize: UInt32 = 0
_NSGetExecutablePath(nil, &executableSize)
var executableBytes = [CChar](repeating: 0, count: Int(executableSize))
guard _NSGetExecutablePath(&executableBytes, &executableSize) == 0 else { exit(1) }
let sibling = URL(fileURLWithPath: String(cString: executableBytes)).resolvingSymlinksInPath()
    .deletingLastPathComponent().appendingPathComponent("Vital")
guard geteuid() == 0, let requirement = FanService.requirement(for: sibling) else { exit(1) }
let helper = Helper(requirement: requirement)
let listener = NSXPCListener(machServiceName: FanService.name)
listener.delegate = helper


// A daemon has no NSWorkspace session. Use IOKit's system power notifications before acknowledging sleep.
var powerPort: IONotificationPortRef?
var notifier: io_object_t = 0
var powerConnection: io_connect_t = 0
powerConnection = IORegisterForSystemPower(nil, &powerPort, { _, _, message, argument in
    if message == UInt32(VS_SYSTEM_WILL_SLEEP) {
        helper.queue.sync { helper.session.reset() }
        IOAllowPowerChange(powerConnection, Int(bitPattern: argument))
    } else if message == UInt32(VS_CAN_SYSTEM_SLEEP) {
        IOAllowPowerChange(powerConnection, Int(bitPattern: argument))
    }
}, &notifier)
if let powerPort, let source = IONotificationPortGetRunLoopSource(powerPort)?.takeUnretainedValue() {
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
}
guard powerConnection != 0, powerPort != nil else { exit(1) }
listener.resume()
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
    helper.queue.sync { helper.session.reset() }
    vs_smc_close()
    exit(0)
}
termination.resume()
RunLoop.main.run()
