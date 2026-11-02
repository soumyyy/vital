import Foundation
import IOKit.pwr_mgt

public struct SleepBlock: Sendable, Equatable {
    public var reason: String
    public var blocksDisplaySleep: Bool
    public var appName: String?       // when a system daemon holds the assertion on an app's behalf
}

public enum SleepBlockers {
    /// macOS's background-task daemon holds assertions for apps, naming the app only inside the text, for
    /// example "... for net.whatsapp.WhatsApp(FinishTask)". Returns "WhatsApp".
    public static func appName(fromAssertionName name: String) -> String? {
        for pattern in [#"for ([A-Za-z0-9_.-]+)\("#, #"application\.([A-Za-z0-9_.-]+?)\.\d"#] {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  let r = Range(m.range(at: 1), in: name) else { continue }
            let last = name[r].split(separator: ".").last.map(String.init)
            if let last, !last.isEmpty { return last }
        }
        return nil
    }

    static let systemTypes: Set<String> = ["PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion"]
    static let displayTypes: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]

    /// Apps that are keeping the Mac (or its display) awake, from the power assertion table. macOS's own
    /// power daemon always holds a "prevent sleep while the display is on" assertion, so it is left out.
    public static func parse(_ raw: [Int: [[String: Any]]], ignoring ignored: Set<Int32> = []) -> [Int32: SleepBlock] {
        var out: [Int32: SleepBlock] = [:]
        for (pidInt, list) in raw {
            let pid = Int32(truncatingIfNeeded: pidInt)
            if ignored.contains(pid) { continue }
            for a in list {
                let type = a["AssertType"] as? String ?? ""
                let name = a["AssertName"] as? String ?? ""
                let isSystem = systemTypes.contains(type), isDisplay = displayTypes.contains(type)
                guard isSystem || isDisplay else { continue }
                if name.hasPrefix("Powerd") { continue }
                let existing = out[pid]
                out[pid] = SleepBlock(reason: existing?.reason ?? (name.isEmpty ? "Keeping the Mac awake" : name),
                                      blocksDisplaySleep: (existing?.blocksDisplaySleep ?? false) || isDisplay,
                                      appName: existing?.appName ?? appName(fromAssertionName: name))
            }
        }
        return out
    }

    public static func read() -> [Int32: SleepBlock] {
        var dict: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&dict) == kIOReturnSuccess,
              let raw = dict?.takeRetainedValue() as? [Int: [[String: Any]]] else { return [:] }
        return parse(raw)
    }
}
