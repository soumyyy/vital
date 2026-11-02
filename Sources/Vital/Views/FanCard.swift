import SwiftUI
import VitalCore

/// Live fan speeds with an Auto / Manual switch. Manual is disabled, with the reason shown, until a
/// privileged helper exists (see docs/superpowers/specs/2026-11-02-fan-control-helper.md).
struct FanCard: View {
    @ObservedObject var model: PanelModel
    @State private var mode = 0       // 0 = Auto, 1 = Manual (display only while unavailable)

    var body: some View {
        let fans = model.snapshot.thermal.fans
        if !fans.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(fans.count == 1 ? "Fan" : "Fans").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Picker("Fan mode", selection: $mode) {
                        Text("Auto").tag(0)
                        Text("Manual").tag(1)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 130)
                    .disabled(!available)
                }
                ForEach(fans, id: \.index) { fan in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            if fans.count > 1 { Text("Fan \(fan.index + 1)").font(.system(size: 11)).foregroundStyle(.secondary) }
                            Spacer()
                            Text(fan.rpm < 1 ? "Idle (0 rpm)" : Format.rpm(fan.rpm))
                                .font(.system(size: 12, weight: .medium)).monospacedDigit()
                        }
                        UsageBar(fraction: fraction(fan), color: Palette.blue)
                        if let lo = fan.minRPM, let hi = fan.maxRPM {
                            HStack {
                                Text("min \(Format.rpm(lo))"); Spacer(); Text("max \(Format.rpm(hi))")
                            }
                            .font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
                        }
                    }
                }
                if case .unavailable(let reason) = model.fanAvailability {
                    Text(reason).font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
            .accessibilityElement(children: .contain)
        }
    }

    private var available: Bool { model.fanAvailability == .available }

    private func fraction(_ fan: FanReading) -> Double {
        guard let hi = fan.maxRPM, hi > 0 else { return 0 }
        return min(1, fan.rpm / hi)
    }
}
