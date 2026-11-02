import SwiftUI
import VitalCore

struct FanCard: View {
    @ObservedObject var model: PanelModel
    var body: some View { FanControls(controller: model.fanController, fans: model.snapshot.thermal.fans) }
}

private struct FanControls: View {
    @ObservedObject var controller: FanClient
    let fans: [FanReading]
    var body: some View {
        if !fans.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(fans.count == 1 ? "Fan" : "Fans").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if controller.availability != .available {
                        Button("Enable control") { controller.enable() }.font(.system(size: 11))
                    }
                }
                ForEach(fans, id: \.index) { fan in
                    FanSlider(controller: controller, fan: fan, multiple: fans.count > 1)
                }
                if let error = controller.error {
                    Text(error).font(.system(size: 10)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if case .unavailable(let reason) = controller.availability {
                    Text(reason).font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.card()
            .onAppear { controller.refresh() }
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
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(multiple ? "Fan \(fan.index + 1)" : "Speed").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text(fan.rpm < 1 ? "Idle (0 rpm)" : Format.rpm(fan.rpm))
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                Button("Auto") { controller.set(fan: fan.index, rpm: -1) }
                    .font(.system(size: 11))
                    .disabled(controller.targets[fan.index] == nil || controller.busy)
            }
            if let lo = fan.minRPM, let hi = fan.maxRPM, lo.isFinite, hi.isFinite, lo > 0, hi > lo {
                Slider(value: Binding(get: {
                    min(hi, max(lo, draft ?? controller.targets[fan.index] ?? max(lo, fan.rpm)))
                }, set: { draft = $0 }), in: lo...hi, onEditingChanged: { active in
                    editing = active
                    if !active, let draft { controller.set(fan: fan.index, rpm: draft) }
                })
                .onChange(of: controller.busy) { _, busy in if !busy { draft = nil } }
                .onChange(of: controller.targets[fan.index]) { _, _ in if !editing { draft = nil } }
                .disabled(controller.availability != .available || controller.busy)
                .accessibilityLabel(multiple ? "Fan \(fan.index + 1) target speed" : "Fan target speed")
                .accessibilityValue("\(Int(draft ?? controller.targets[fan.index] ?? fan.rpm)) rpm")
                HStack {
                    Text(Format.rpm(lo)); Spacer()
                    Text(editing ? Format.rpm(draft ?? lo) : controller.targets[fan.index].map { Format.rpm($0) } ?? "Auto")
                    Spacer(); Text(Format.rpm(hi))
                }.font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}
