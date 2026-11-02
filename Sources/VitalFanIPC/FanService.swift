import Foundation
import Security

public enum FanService {
    public static let name = "dev.soumya.vital.fan-control"
    public static let legacyPlist = "dev.soumya.vital.fans.plist"
    public static let plist = name + ".plist"

    public static func registrationError(bundle: URL = Bundle.main.bundleURL) -> String? {
        guard bundle.resolvingSymlinksInPath().path == "/Applications/Vital.app" else {
            return "Install Vital in /Applications before enabling fan control."
        }
        var code: SecStaticCode?
        var rule: SecRequirement?
        let requirement = "anchor apple generic and identifier \"dev.soumya.vital\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess,
              SecRequirementCreateWithString(requirement as CFString, [], &rule) == errSecSuccess,
              let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode), rule) == errSecSuccess else {
            return "Fan control requires the Developer ID-signed release. Development builds cannot replace the installed helper."
        }
        return nil
    }

    /// Pins a peer by who signed it, so any release of Vital works with any release of the helper. A pin to one
    /// exact build breaks every update: the old helper keeps running and refuses the new app. Falls back to the
    /// exact build for local ad hoc signatures, which have no team to name.
    public static func requirement(for executable: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executable as CFURL, [], &code) == errSecSuccess,
              let code, SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        if let team = dict[kSecCodeInfoTeamIdentifier as String] as? String,
           let identifier = dict[kSecCodeInfoIdentifier as String] as? String,
           let rule = identityRequirement(identifier: identifier, team: team) { return rule }
        guard let hash = dict[kSecCodeInfoUnique as String] as? Data else { return nil }
        return "cdhash H\"" + hash.map { String(format: "%02x", $0) }.joined() + "\""
    }

    /// Apple-issued certificate, this signing identifier, this team. Both values are checked for a safe shape so
    /// they can be placed inside a requirement string.
    public static func identityRequirement(identifier: String, team: String) -> String? {
        let safeID = identifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        let safeTeam = team.count == 10 && team.allSatisfy { $0.isUppercase || $0.isNumber }
        guard safeID, safeTeam, !identifier.isEmpty else { return nil }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// The code directory hash of the helper bundled in an app. A different value from the running helper means
    /// the helper process is left over from an older install and must be restarted.
    public static func bundledHelperBuild(app: URL = Bundle.main.bundleURL) -> String? {
        let helper = app.appendingPathComponent("Contents/MacOS/VitalFanHelper")
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(helper as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let hash = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else { return nil }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

@objc public protocol FanServiceProtocol {
    /// rpm = -1 selects automatic. Every other value must be a finite manual target.
    func set(fan: Int, rpm: Double, reply: @escaping (String?) -> Void)
    /// Also renews the manual-control lease. Keys are fan indices, values are acknowledged targets.
    func status(reply: @escaping ([String: NSNumber], String?) -> Void)
}
