import AppKit
import CryptoKit
import Security
import VitalCore

/// Checks GitHub for a newer release and installs it over the running app. Nothing here runs unless the
/// person presses a button: Vital makes no network request on its own.
@MainActor
final class UpdateModel: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(ReleaseInfo)
        case downloading, installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    let current: AppVersion
    let displayVersion: String

    private let feedURL: URL
    private let installTarget: URL

    init() {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String
        current = AppVersion(short) ?? AppVersion("0")!
        displayVersion = build.map { "\(short) (\($0))" } ?? short
        func arg(_ name: String) -> String? {
            CommandLine.arguments.first { $0.hasPrefix("--\(name)=") }.map { String($0.dropFirst(name.count + 3)) }
        }
        // Test hooks: point the check at another feed, or install somewhere other than the running app.
        feedURL = arg("update-feed").flatMap(URL.init(string:)) ?? UpdateFeed.defaultURL
        installTarget = arg("update-target").map { URL(fileURLWithPath: $0) } ?? Bundle.main.bundleURL
    }

    var isBusy: Bool { state == .checking || state == .downloading || state == .installing }

    // MARK: check

    func check() {
        guard !isBusy else { return }
        state = .checking
        Task { [feedURL, current] in
            do {
                let data = try await Self.fetch(feedURL)
                guard let release = UpdateFeed.parse(data) else {
                    state = .failed("The latest release has no downloadable Vital app.")
                    return
                }
                state = UpdatePolicy.decide(current: current, latest: release) == .upToDate ? .upToDate : .available(release)
            } catch let error as UpdateError {
                state = .failed(error.message)
            } catch {
                state = .failed("Could not reach the update server. Check your connection and try again.")
            }
        }
    }

    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Vital", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError(http.statusCode == 404 ? "No release has been published yet." : "The update server answered with an error (\(http.statusCode)).")
        }
        return data
    }

    // MARK: install

    func install() {
        guard case .available(let release) = state, !isBusy else { return }
        state = .downloading
        Task { [installTarget, current] in
            let work = installTarget.deletingLastPathComponent().appendingPathComponent(".vital-update-\(UUID().uuidString.prefix(8))")
            var restoreHelperOnFailure = false
            do {
                guard FileManager.default.isWritableFile(atPath: installTarget.deletingLastPathComponent().path) else {
                    throw UpdateError("Vital can't replace itself in this folder. Download the new version from the release page instead.")
                }
                Self.removeLeftovers(beside: installTarget)
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                defer {
                    // Preserve the backup if the target disappeared during an interrupted installation.
                    let backup = work.appendingPathComponent("old.app")
                    if FileManager.default.fileExists(atPath: installTarget.path) || !FileManager.default.fileExists(atPath: backup.path) {
                        try? FileManager.default.removeItem(at: work)
                    }
                }

                let (tmp, response) = try await URLSession(configuration: .ephemeral).download(from: release.assetURL)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw UpdateError("The download failed (\(http.statusCode)).")
                }
                let zip = work.appendingPathComponent(release.assetName)
                try FileManager.default.moveItem(at: tmp, to: zip)

                state = .installing
                if let expected = release.sha256, try Self.sha256(of: zip) != expected {
                    throw UpdateError("The download does not match its published checksum, so it was discarded.")
                }
                let unpacked = work.appendingPathComponent("new")
                try await Self.unzip(zip, to: unpacked)
                guard let newApp = try FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
                    .first(where: { $0.pathExtension == "app" }) else { throw UpdateError("The download did not contain an app.") }
                try UpdateVerifier.check(newApp, running: Bundle.main.bundleURL, expected: release.version, current: current)
                restoreHelperOnFailure = try await FanClient.prepareForUpdate()          // the helper is tied to the old bundle's signature
                try UpdateBundleSwap.replace(installTarget, with: newApp, in: work)
                try Self.relaunch(installTarget)
                try? FileManager.default.removeItem(at: work)
                NSApp.terminate(nil)
            } catch {
                let message = (error as? UpdateError)?.message ?? "The update failed: \(error.localizedDescription)"
                let recovery = restoreHelperOnFailure ? FanClient.completeUpdate() : nil
                state = .failed([message, recovery].compactMap { $0 }.joined(separator: " "))
            }
        }
    }

    /// Work folders left by an update that was interrupted.
    private static func removeLeftovers(beside target: URL) {
        let dir = target.deletingLastPathComponent()
        for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])) ?? []
        where url.lastPathComponent.hasPrefix(".vital-update-") {
            guard !FileManager.default.fileExists(atPath: url.appendingPathComponent("old.app").path) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// A short shell waits for this process to exit, then opens the new app.
    private static func relaunch(_ app: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \"$VITAL_PID\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open -n \"$VITAL_APP\""]
        p.environment = ["VITAL_PID": String(getpid()), "VITAL_APP": app.path]
        do { try p.run() }
        catch { throw UpdateError("The update is installed. Quit and reopen Vital to finish restarting.") }
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func unzip(_ zip: URL, to dir: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", zip.path, dir.path]
            p.terminationHandler = { proc in
                proc.terminationStatus == 0 ? cont.resume() : cont.resume(throwing: UpdateError("The download could not be unpacked."))
            }
            do { try p.run() } catch { cont.resume(throwing: UpdateError("The download could not be unpacked.")) }
        }
    }
}

struct UpdateError: Error { let message: String; init(_ m: String) { message = m } }

/// Refuses anything that is not a correctly signed Vital from the same developer as the running copy.
enum UpdateVerifier {
    static func check(_ new: URL, running: URL, expected: AppVersion, current: AppVersion) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(new as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateError("The downloaded app could not be read.")
        }
        guard SecStaticCodeCheckValidityWithErrors(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures), nil, nil) == errSecSuccess else {
            throw UpdateError("The downloaded app's signature is not valid, so it was not installed.")
        }
        let info = Bundle(url: new)?.infoDictionary
        guard info?["CFBundleIdentifier"] as? String == "dev.soumya.vital" else { throw UpdateError("The download is not Vital.") }
        guard let v = (info?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init), v == expected, v > current else {
            throw UpdateError("The download is not the version the release announced.")
        }
        let newTeam = team(of: code)
        var runningCode: SecStaticCode?
        SecStaticCodeCreateWithPath(running as CFURL, [], &runningCode)
        let runningTeam = runningCode.flatMap(team(of:))
        if let runningTeam {
            guard newTeam == runningTeam else { throw UpdateError("The download is signed by a different developer, so it was not installed.") }
            var requirement: SecRequirement?
            let rule = "anchor apple generic and identifier \"dev.soumya.vital\" and certificate leaf[subject.OU] = \"\(runningTeam)\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
                  SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else {
                throw UpdateError("The update must be signed with this developer's Apple-issued Developer ID certificate.")
            }
        } else {
            throw UpdateError("This copy has no developer signing identity. Install the official signed release before using automatic updates.")
        }
    }

    private static func team(of code: SecStaticCode) -> String? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

/// `Vital --probe-update [--install]` checks the feed from the command line, and with --install updates.
enum UpdateCLI {
    static func runIfRequested(_ args: ArraySlice<String>) -> Bool {
        guard args.contains("--probe-update") else { return false }
        _ = NSApplication.shared
        MainActor.assumeIsolated {
            let model = UpdateModel()
            print("Running \(model.displayVersion)")
            model.check()
            @MainActor func settle(_ done: (UpdateModel.State) -> Bool, seconds: Double) {
                let end = Date().addingTimeInterval(seconds)
                while !done(model.state) && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            }
            settle({ $0 != .checking }, seconds: 20)
            print("After check: \(model.state)")
            if args.contains("--install"), case .available = model.state {
                model.install()
                settle({ if case .failed = $0 { return true }; return false }, seconds: 60)     // success terminates the process
                print("After install: \(model.state)")
            }
        }
        return true
    }
}
