import SwiftUI
import VitalCore

/// Fan speed, shown first on the Heat view. One button turns control on; once on, a switch toggles
/// manual speed and Auto, and a slider sets the speed.
struct FanCard: View {
    @ObservedObject var model: PanelModel
    var body: some View { FanControls(controller: model.fanController, fans: model.snapshot.thermal.fans) }
}

private struct FanControls: View {
    @ObservedObject var controller: FanClient
    let fans: [FanReading]

    private var manual: Bool { controller.isManual }
    private var rpm: Double { fans.map(\.rpm).max() ?? 0 }

    var body: some View {
        if !fans.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "fan").font(.system(size: 15, weight: .medium))
                        .foregroundStyle(manual ? Palette.blue : Color.primary.opacity(0.55)).frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(fans.count == 1 ? "Fan" : "Fans").font(Typo.mediumBold)
                        Text(summary).font(Typo.small).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer(minLength: 4)
                    control
                }
                if controller.connected && manual {
                    ForEach(fans, id: \.index) { fan in FanSlider(controller: controller, fan: fan, multiple: fans.count > 1) }
                }
                if let error = controller.error {
                    Text(error).font(Typo.small).foregroundStyle(Palette.red).fixedSize(horizontal: false, vertical: true)
                } else if !controller.connected, !controller.connecting, controller.needsApproval,
                          case .unavailable(let reason) = controller.availability {
                    Text(reason).font(Typo.small).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
            .onAppear { controller.refresh() }
        }
    }

    private var summary: String {
        let current = rpm < 1 ? "Idle" : Format.rpm(rpm)
        return manual ? "\(current) · Manual" : "\(current) · Automatic"
    }

    @ViewBuilder private var control: some View {
        if controller.connecting || controller.busy {
            ProgressView().controlSize(.small)
                .accessibilityLabel(controller.busy ? "Applying fan speed" : "Connecting to fan control")
        } else if controller.connected {
            Toggle("Manual fan speed", isOn: Binding(get: { manual }, set: { controller.setManual($0, fans: fans) }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                .help(manual ? "Return the fan to Auto" : "Set the fan speed yourself")
        } else {
            Button(controller.setupTitle == "Enable control" ? "Turn on" : controller.setupTitle) { controller.enable() }
                .buttonStyle(PillButton(prominent: true))
                .help("macOS asks for approval the first time")
        }
    }
}

private struct FanSlider: View {
    @ObservedObject var controller: FanClient
    let fan: FanReading
    let multiple: Bool
    @State private var draft: Double?
    @State private var editing = false

    var body: some View {
        if let lo = fan.minRPM, let hi = fan.maxRPM, lo.isFinite, hi.isFinite, lo > 0, hi > lo {
            VStack(alignment: .leading, spacing: 3) {
                if multiple { Text("Fan \(fan.index + 1)").font(Typo.small).foregroundStyle(.secondary) }
                Slider(value: Binding(get: {
                    min(hi, max(lo, draft ?? controller.targets[fan.index] ?? max(lo, fan.rpm)))
                }, set: { draft = $0 }), in: lo...hi, onEditingChanged: { active in
                    editing = active
                    if !active, let draft { controller.set(fan: fan.index, rpm: draft) }
                })
                .tint(Palette.blue)
                .onChange(of: controller.busy) { _, busy in if !busy { draft = nil } }
                .onChange(of: controller.targets[fan.index]) { _, _ in if !editing { draft = nil } }
                .disabled(controller.busy)
                .accessibilityLabel(multiple ? "Fan \(fan.index + 1) target speed" : "Fan target speed")
                .accessibilityValue("\(Int(draft ?? controller.targets[fan.index] ?? fan.rpm)) rpm")
                HStack {
                    Text(Format.rpm(lo)); Spacer()
                    Text(Format.rpm(draft ?? controller.targets[fan.index] ?? lo)).foregroundStyle(.primary)
                    Spacer(); Text(Format.rpm(hi))
                }.font(Typo.small).foregroundStyle(.secondary).monospacedDigit()
            }
        } else {
            Text("Manual control is unavailable for this fan.").font(Typo.small).foregroundStyle(.secondary)
        }
    }
}
