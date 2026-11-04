import SwiftUI

// MARK: - Color

// Rymynd is dark-only by design: deep graphite, Liquid Glass, and light used like a signal.
extension Color {
    static let canvas = Color(red: 0.024, green: 0.027, blue: 0.035)
    /// Flat raised surface, for the rare places glass would sit on glass.
    static let surface = Color.white.opacity(0.06)
    static let ink = Color(white: 0.97)
    static let ink2 = Color.white.opacity(0.56)
    static let ink3 = Color.white.opacity(0.30)
    static let hairline = Color.white.opacity(0.09)
    /// The app's own accent.
    static let accent = Color(white: 0.95)
}

// MARK: - Type

extension Font {
    /// SF Pro Display — tight, confident headings.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .default, weight: weight)
    }

    static func display(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// SF Mono — labels, counts and timestamps, for an instrument-panel feel.
    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .medium) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Monospaced, tracked uppercase label used above sections and in cards.
    func eyebrow(_ color: Color = .ink2) -> some View {
        font(.mono(.caption2, weight: .medium))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(color)
    }

    /// Haptics that respect the user's preference.
    func haptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        sensoryFeedback(trigger: trigger) { _, _ in Prefs.haptics ? feedback : nil }
    }
}

// MARK: - Motion

enum Motion {
    static let snappy = Animation.snappy(duration: 0.32, extraBounce: 0.06)
    static let smooth = Animation.smooth(duration: 0.45)
    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.62)
    static let gentle = Animation.spring(response: 0.6, dampingFraction: 0.86)
}

// MARK: - Time formatting

enum TimeFormat {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func day(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if (2...6).contains(days) { return date.formatted(.dateTime.weekday(.wide)) }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static func dayAndTime(_ date: Date, now: Date = .now) -> String {
        "\(day(date, now: now)), \(time(date))"
    }

    /// "in 42 min", "in 3 h 5 min", "in 2 days", "12 min ago".
    static func relative(_ date: Date, now: Date = .now) -> String {
        let seconds = date.timeIntervalSince(now)
        let minutes = Int((abs(seconds) / 60).rounded(seconds >= 0 ? .up : .down))
        if abs(seconds) < 60 { return seconds >= 0 ? "in a moment" : "just now" }
        let phrase: String
        switch minutes {
        case ..<60: phrase = "\(minutes) min"
        case ..<(60 * 24):
            let hours = minutes / 60, rest = minutes % 60
            phrase = rest == 0 || hours >= 6 ? "\(hours) h" : "\(hours) h \(rest) min"
        default:
            let days = Int((Double(minutes) / 1440).rounded())
            phrase = days == 1 ? "1 day" : "\(days) days"
        }
        return seconds >= 0 ? "in \(phrase)" : "\(phrase) ago"
    }

    /// "42:07" countdown for the last hour.
    static func countdown(_ date: Date, now: Date = .now) -> String {
        let remaining = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
        let h = remaining / 3600, m = (remaining % 3600) / 60, s = remaining % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
