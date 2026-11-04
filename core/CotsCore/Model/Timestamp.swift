import Foundation

public enum Timestamp {
    // Thread-safe for parsing and formatting; only reconfiguring it isn't, and it's never
    // changed after creation. (Unlike DateFormatter, it isn't marked Sendable.)
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    private static let lenient: [DateFormatter] = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss",
                                                   "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = $0
        return f
    }

    public static func now() -> String { string(from: Date()) }

    public static func string(from date: Date) -> String { formatter.string(from: date) }

    public static func parse(_ string: String) -> Date? {
        let s = string.trimmingCharacters(in: .whitespaces)
        if let d = fastParse(s) { return d }
        if let d = formatter.date(from: s) { return d }
        for f in lenient { if let d = f.date(from: s) { return d } }
        return nil
    }
}

extension Timestamp {
    /// `yyyy-MM-ddTHH:mm:ss` followed by `Z` or `±HH:MM`, the format coTs writes. Parsed by
    /// hand because `ISO8601DateFormatter` is slow enough to dominate listing thousands of notes.
    static func fastParse(_ s: String) -> Date? {
        let b = Array(s.utf8)
        guard b.count == 20 || b.count == 25, b[4] == 45, b[7] == 45, b[10] == 84, b[13] == 58, b[16] == 58 else { return nil }
        func num(_ from: Int, _ len: Int) -> Int? {
            var n = 0
            for i in from..<(from + len) {
                guard b[i] >= 48, b[i] <= 57 else { return nil }
                n = n * 10 + Int(b[i] - 48)
            }
            return n
        }
        guard let year = num(0, 4), let month = num(5, 2), let day = num(8, 2),
              let hour = num(11, 2), let minute = num(14, 2), let second = num(17, 2),
              (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 61 else { return nil }
        var offset = 0
        if b.count == 20 {
            guard b[19] == 90 else { return nil } // Z
        } else {
            guard b[19] == 43 || b[19] == 45, b[22] == 58, let oh = num(20, 2), let om = num(23, 2) else { return nil }
            offset = (oh * 3600 + om * 60) * (b[19] == 45 ? -1 : 1)
        }
        // Days since 1970-01-01 (Howard Hinnant's days_from_civil).
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146097 + doe - 719468
        return Date(timeIntervalSince1970: TimeInterval(days * 86400 + hour * 3600 + minute * 60 + second - offset))
    }
}
