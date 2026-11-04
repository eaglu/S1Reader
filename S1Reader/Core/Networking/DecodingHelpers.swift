import Foundation

/// Discuz! returns almost every scalar as a string, but occasionally as a number.
/// These helpers accept either representation.
extension KeyedDecodingContainer {
    func flexString(_ key: Key) -> String {
        flexStringOptional(key) ?? ""
    }

    func flexStringOptional(_ key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) {
            return String(Int(value))
        }
        return nil
    }

    func flexInt(_ key: Key) -> Int {
        Int(flexString(key)) ?? 0
    }

    func flexBool(_ key: Key) -> Bool {
        let raw = flexString(key)
        return raw == "1" || raw.lowercased() == "true"
    }

    func nested<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }
}

extension JSONDecoder {
    static let discuz: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()
}

enum Formatters {
    static let serverDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func date(from string: String) -> Date? {
        serverDate.date(from: string)
    }

    /// "2024-11-12 19:01" -> "刚刚" / "3 小时前" / "11月12日"
    static func relative(_ string: String) -> String {
        guard let date = date(from: string) else { return string }
        return relative(date)
    }

    static func relative(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86_400 { return "\(Int(interval / 3600)) 小时前" }
        if interval < 86_400 * 7 { return "\(Int(interval / 86_400)) 天前" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) ? "M月d日" : "yyyy年M月d日"
        return formatter.string(from: date)
    }

    static func compactCount(_ value: Int) -> String {
        if value >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000)
        }
        return String(value)
    }
}
