import Foundation
import Security

public enum FanService {
    public static let name = "dev.soumya.vital.fans"
    public static let plist = name + ".plist"

    /// Pin each peer to the exact signed executable shipped beside it. Works with local ad-hoc builds
    /// as well as certificate signing. XPC checks the running peer, avoiding PID reuse checks.
    public static func requirement(for executable: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executable as CFURL, [], &code) == errSecSuccess,
              let code, SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
              let hash = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else { return nil }
        return "cdhash H\"" + hash.map { String(format: "%02x", $0) }.joined() + "\""
    }
}

@objc public protocol FanServiceProtocol {
    /// rpm = -1 selects automatic. Every other value must be a finite manual target.
    func set(fan: Int, rpm: Double, reply: @escaping (String?) -> Void)
    /// Also renews the manual-control lease. Keys are fan indices, values are acknowledged targets.
    func status(reply: @escaping ([String: NSNumber], String?) -> Void)
}
