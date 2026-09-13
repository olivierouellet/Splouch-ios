import Foundation

/// Signed delta versus seed, from `lane_delta_seconds<i>` / `delta_seconds`.
/// Same rule as the server's own formatter and the Qt display: hundredths,
/// switching to `m:ss.hh` past a minute. Empty when there is no delta.
public enum DeltaFormat {
    public static func text(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "" }
        var h = Int((seconds * 100).rounded())
        let sign = h < 0 ? "-" : "+"
        h = abs(h)
        let minutes = h / 6000
        let secs = (h / 100) % 60
        let frac = h % 100
        let f = frac < 10 ? "0\(frac)" : "\(frac)"
        if minutes > 0 {
            return "\(sign)\(minutes):" + (secs < 10 ? "0" : "") + "\(secs).\(f)"
        }
        return "\(sign)\(secs).\(f)"
    }
}
