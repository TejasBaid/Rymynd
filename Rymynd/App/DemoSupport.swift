#if DEBUG
import Foundation

/// Debug-only launch arguments for screenshots and manual QA:
/// `-skipOnboarding`, `-resetOnboarding`, `-seedDemo`, `-openWizard`, `-openSettings`,
/// `-compose "<text>"`, `-onboardingPage <n>`.
enum DemoSupport {
    static let arguments = ProcessInfo.processInfo.arguments

    static func has(_ flag: String) -> Bool { arguments.contains(flag) }

    static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    @MainActor
    static func applyLaunchArguments() {
        if has("-skipOnboarding") { AppGroup.defaults.set(true, forKey: Prefs.Key.hasOnboarded) }
        if has("-resetOnboarding") { AppGroup.defaults.set(false, forKey: Prefs.Key.hasOnboarded) }
        if has("-seedDemo") { ReminderStore.shared.replaceAll(with: demoReminders(), completions: demoCompletions()) }
    }

    private static func demoReminders(now: Date = .now) -> [Reminder] {
        let calendar = Calendar.current
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now))!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        return [
            Reminder(title: "Call Mom about the flights", notes: "She found cheaper ones", dueDate: now.addingTimeInterval(18 * 60 + 40).roundedToMinute, tint: .cobalt, symbol: "phone", createdAt: now.addingTimeInterval(-3 * 3600), origin: .intelligence),
            Reminder(title: "Take vitamins", dueDate: now.addingTimeInterval(-6 * 60).roundedToMinute, repeatRule: .daily, tint: .ice, symbol: "pills"),
            Reminder(title: "Pick up dry cleaning", dueDate: now.addingTimeInterval(3 * 3600).roundedToMinute, tint: .volt, symbol: "cart"),
            Reminder(title: "Water the plants", dueDate: at(1, 9), repeatRule: .weekly, tint: .mint, symbol: "leaf"),
            Reminder(title: "Submit the expense report", dueDate: at(3, 10), delivery: .ring, tint: .violet, symbol: "briefcase"),
            Reminder(title: "Book the dentist", dueDate: at(12, 11), delivery: .nudge, tint: .ice, symbol: "heart"),
            Reminder(title: "Renew passport", tint: .cobalt, symbol: "airplane"),
        ]
    }

    private static func demoCompletions(now: Date = .now) -> [CompletionRecord] {
        let calendar = Calendar.current
        var records = [
            CompletionRecord(snapshot: Reminder(title: "Morning run", tint: .mint, symbol: "figure.run"), completedAt: now.addingTimeInterval(-4 * 3600)),
            CompletionRecord(snapshot: Reminder(title: "Reply to Sam", tint: .cobalt, symbol: "message"), completedAt: now.addingTimeInterval(-2 * 3600)),
        ]
        for day in 1...4 {
            let date = calendar.date(byAdding: .day, value: -day, to: now)!
            records.append(CompletionRecord(snapshot: Reminder(title: "Stretch", tint: .mint, symbol: "figure.run"), completedAt: date))
        }
        return records
    }
}
#endif
