import SwiftUI
import VitalCore

/// CPU, Memory, Storage and Heat: one number each. The tiles are also the selector for the list below.
struct VitalTiles: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PanelTab.allCases) { tab in tile(tab) }
        }
    }

    private func tile(_ tab: PanelTab) -> some View {
        let r = reading(tab)
        let selected = model.tab == tab
        return Button { model.select(tab) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(tab.rawValue).font(Typo.small).foregroundStyle(selected ? .primary : .secondary)
                Text(r.value).font(Typo.number).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(r.fraction == nil ? .secondary : .primary)
                Meter(fraction: r.fraction, level: r.level).padding(.top, 2)
            }
            .padding(.horizontal, 9).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Color.primary.opacity(0.09) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tab.rawValue), \(r.spoken)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Shows what is using the most \(tab == .heat ? "power" : tab.rawValue.lowercased())")
    }

    fileprivate struct Reading { var value: String; var fraction: Double?; var level: HealthLevel; var spoken: String }

    private func reading(_ tab: PanelTab) -> Reading {
        let s = model.snapshot
        let missing = s.date == .distantPast ? "…" : "n/a"
        switch tab {
        case .cpu:
            guard let c = s.cpu else { return Reading(value: missing, level: .good, spoken: "unavailable") }
            return Reading(value: Format.percent(c.total), fraction: c.total, level: Health.cpu(c.total),
                           spoken: "\(Format.percent(c.total)) in use")
        case .memory:
            guard let m = s.memory else { return Reading(value: missing, level: .good, spoken: "unavailable") }
            return Reading(value: Format.percent(m.usedFraction), fraction: m.usedFraction, level: Health.memory(m.pressure),
                           spoken: "\(Format.percent(m.usedFraction)) in use")
        case .storage:
            guard let st = s.storage else { return Reading(value: missing, level: .good, spoken: "unavailable") }
            return Reading(value: Format.percent(st.usedFraction), fraction: st.usedFraction, level: Health.storage(usedFraction: st.usedFraction),
                           spoken: "\(Format.percent(st.usedFraction)) full")
        case .heat:
            let level = Health.heat(s.thermal.state)
            guard let c = s.thermal.hottestCelsius else {
                // No temperature sensor: show macOS's own word instead of a number.
                return Reading(value: s.date == .distantPast ? "…" : Self.word(s.thermal.state), level: level, spoken: Self.word(s.thermal.state))
            }
            return Reading(value: "\(Int(c.rounded()))°", fraction: ThermalMath.scaleFraction(celsius: c), level: level,
                           spoken: "\(Int(c.rounded())) degrees Celsius")
        }
    }

    static func word(_ s: ThermalState) -> String {
        switch s { case .nominal: return "Normal"; case .fair: return "Warm"; case .serious: return "Hot"; case .critical: return "Critical" }
    }
}

private extension VitalTiles.Reading {
    init(value: String, level: HealthLevel, spoken: String) { self.init(value: value, fraction: nil, level: level, spoken: spoken) }
}
