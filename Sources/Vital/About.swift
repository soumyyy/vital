import AppKit
import SwiftUI
import VitalCore

/// The About window: what Vital is, its version, and the Update Software controls. Exists only while open.
@MainActor
enum AboutPanel {
    private static var window: NSWindow?
    private static var model: UpdateModel?
    private static var closing: NSObjectProtocol?

    /// `checkNow` starts an update check as the window opens (the Update Software menu item).
    static func show(checkNow: Bool = false) {
        if let window, let model {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if checkNow { model.check() }
            return
        }
        let model = UpdateModel()
        let host = NSHostingView(rootView: AboutView(model: model))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 300), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "About Vital"
        w.contentView = host
        w.isReleasedWhenClosed = false
        w.setContentSize(host.fittingSize)
        w.center()
        closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated {
                window = nil; Self.model = nil
                if let c = closing { NotificationCenter.default.removeObserver(c); closing = nil }
            }
        }
        window = w; Self.model = model
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        if checkNow { model.check() }
    }
}

private struct AboutView: View {
    @ObservedObject var model: UpdateModel

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            VStack(spacing: 3) {
                Text("Vital").font(.system(size: 20, weight: .semibold))
                Text("Version \(model.displayVersion)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("Vital is an open-source tool, made to make your life easier.")
                .font(.system(size: 12)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Divider()
            UpdateSection(model: model)
            Text("MIT licensed").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 28).padding(.vertical, 24)
        .frame(width: 320)
    }
}

private struct UpdateSection: View {
    @ObservedObject var model: UpdateModel

    var body: some View {
        VStack(spacing: 10) {
            switch model.state {
            case .idle:
                Button("Update Software") { model.check() }
            case .checking:
                progress("Checking for updates…")
            case .upToDate:
                Label("Vital is up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12))
                Button("Check Again") { model.check() }.buttonStyle(.link).font(.system(size: 11))
            case .available(let release):
                Text("Vital \(release.version.text) is available").font(.system(size: 12, weight: .semibold))
                let notes = UpdatePolicy.summary(of: release.notes, limit: 240)
                if !notes.isEmpty {
                    Text(notes).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Update and Restart") { model.install() }.keyboardShortcut(.defaultAction)
                if let page = release.pageURL { Link("Release notes", destination: page).font(.system(size: 11)) }
            case .downloading:
                progress("Downloading…")
            case .installing:
                progress("Installing…")
            case .failed(let message):
                Text(message).font(.system(size: 11)).foregroundStyle(.red).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { model.check() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(text).font(.system(size: 12)).foregroundStyle(.secondary) }
    }
}
