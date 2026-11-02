import Foundation

public enum Format {
    public enum Base { case decimal, binary }

    public static func bytes(_ n: UInt64, base: Base) -> String {
        let step: Double = base == .decimal ? 1000 : 1024
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(n)
        var i = 0
        while value >= step && i < units.count - 1 { value /= step; i += 1 }
        if i == 0 { return "\(Int(value)) B" }
        let text = value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(text) \(units[i])"
    }

    public static func percent(_ fraction: Double) -> String {
        let clamped = min(max(fraction, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    public static func rpm(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return "\(f.string(from: NSNumber(value: v)) ?? "\(Int(v))") rpm"
    }

    /// Share of the whole CPU, for example "23%". Anything above zero but under 1% reads "<1%".
    public static func cpuShare(cores: Double, coreCount: Int) -> String {
        let share = CPUMath.shareOfTotal(cores: cores, coreCount: coreCount)
        if share > 0 && share < 0.005 { return "<1%" }
        return "\(Int((share * 100).rounded()))%"
    }

    /// Activity Monitor style: 100% is one full core, so a busy app can read above 100%.
    public static func ofOneCore(_ cores: Double) -> String { "\(Int((max(0, cores) * 100).rounded()))% of a core" }

    /// "2.7 of 8 cores"
    public static func coresInUse(_ cores: Double, of count: Int) -> String {
        String(format: "%.1f of %d cores", min(max(0, cores), Double(count)), count)
    }
}
