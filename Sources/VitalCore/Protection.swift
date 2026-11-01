import Foundation

public enum Protection {
    static let protectedNames: Set<String> = ["kernel_task", "launchd", "WindowServer", "loginwindow"]

    /// Processes Vital must never offer to kill.
    public static func isProtected(pid: Int32, name: String, selfPid: Int32 = getpid()) -> Bool {
        pid <= 1 || pid == selfPid || protectedNames.contains(name)
    }
}
