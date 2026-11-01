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
}
