import Foundation
import Darwin

public enum UpdateInstallError: LocalizedError {
    case replacementFailed
    public var errorDescription: String? {
        switch self {
        case .replacementFailed: return "Could not put the new version in place. The old one was kept."
        }
    }
}

public enum UpdateBundleSwap {
    /// Keep a backup, then exchange paths in one filesystem operation. A process crash
    /// must never leave the normal app path absent between two separate moves.
    public static func replace(_ target: URL, with new: URL, in work: URL, files: FileManager = .default,
                               exchange: ((URL, URL) throws -> Void)? = nil) throws {
        let old = work.appendingPathComponent("old.app")
        try files.copyItem(at: target, to: old)
        do {
            if let exchange { try exchange(target, new) }
            else if renamex_np(target.path, new.path, UInt32(RENAME_SWAP)) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch { throw UpdateInstallError.replacementFailed }
    }
}
