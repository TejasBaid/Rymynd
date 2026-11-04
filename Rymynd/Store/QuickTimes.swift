import Foundation

/// The handful of times people actually mean. Shared by the wizard, menus and the preview card.
enum QuickTimes {
    static func inMinutes(_ minutes: Int, now: Date = .now) -> Date {
        now.addingTimeInterval(TimeInterval(minutes * 60)).roundedToMinute
    }

    /// Later today at the evening hour, or tomorrow evening if that's passed.
    static func evening(now: Date = .now) -> Date {
        at(hour: Prefs.eveningHour, onOrAfter: now)
    }

    static func tomorrowMorning(now: Date = .now) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: Prefs.morningHour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    /// Saturday morning (or today, if it's Saturday morning still).
    static func weekend(now: Date = .now) -> Date {
        let calendar = Calendar.current
        var components = DateComponents()
        components.weekday = 7
        components.hour = max(Prefs.morningHour, 10)
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now
    }

    /// Next Monday morning.
    static func nextWeek(now: Date = .now) -> Date {
        let calendar = Calendar.current
        var components = DateComponents()
        components.weekday = 2
        components.hour = Prefs.morningHour
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now
    }

    static func at(hour: Int, minute: Int = 0, onOrAfter now: Date) -> Date {
        let calendar = Calendar.current
        let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// A sensible default for a fresh reminder: the next half hour, at least 30 minutes out.
    static func suggested(now: Date = .now) -> Date {
        let calendar = Calendar.current
        let ahead = now.addingTimeInterval(30 * 60)
        let minute = calendar.component(.minute, from: ahead)
        let rounded = minute <= 30 ? 30 : 60
        return calendar.date(byAdding: .minute, value: rounded - minute, to: ahead)?.roundedToMinute ?? ahead
    }
}
