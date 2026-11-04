import Foundation

// MARK: - Reminder

/// A single thing worth remembering. Value type, persisted as JSON in the App Group container.
struct Reminder: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    var notes: String = ""
    /// The anchor time. For repeating reminders this is the current occurrence.
    var dueDate: Date?
    /// A temporary override of `dueDate` set by snoozing. Cleared on completion.
    var snoozedUntil: Date?
    var repeatRule: RepeatRule = .never
    var delivery: Delivery = .live
    var tint: ReminderTint = .signal
    var symbol: String = "sparkle"
    var createdAt: Date = .now
    var completionCount: Int = 0
    var origin: Origin = .typed
    var prompt: String?

    enum Origin: String, Codable, Sendable {
        case typed, wizard, intelligence, shortcut
    }

    /// The moment the reminder should actually reach you.
    var fireDate: Date? { snoozedUntil ?? dueDate }

    func isOverdue(at now: Date = .now) -> Bool {
        guard let fireDate else { return false }
        return fireDate <= now
    }

    var isSnoozed: Bool { snoozedUntil != nil }
}

/// A completed occurrence. Holds a snapshot of the reminder *before* completion so it can be undone.
struct CompletionRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var snapshot: Reminder
    var completedAt: Date = .now
}

// MARK: - Repeat

enum RepeatRule: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case never, daily, weekdays, weekly, monthly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: "Once"
        case .daily: "Every day"
        case .weekdays: "Weekdays"
        case .weekly: "Every week"
        case .monthly: "Every month"
        case .yearly: "Every year"
        }
    }

    var shortLabel: String {
        switch self {
        case .never: "Once"
        case .daily: "Daily"
        case .weekdays: "Weekdays"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    func next(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .never:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekdays:
            var candidate = date
            repeat {
                guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = next
            } while calendar.isDateInWeekend(candidate)
            return candidate
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }

    /// The first occurrence strictly after `reference`, walking forward from `anchor`.
    func occurrence(from anchor: Date, after reference: Date, calendar: Calendar = .current) -> Date? {
        guard self != .never else { return nil }
        var candidate = anchor
        var guardrail = 0
        while candidate <= reference, guardrail < 4000 {
            guard let next = next(after: candidate, calendar: calendar) else { return nil }
            candidate = next
            guardrail += 1
        }
        return candidate
    }

    /// Whether `day` would contain an occurrence for a rule anchored at `anchor`. Used for the calendar preview.
    func occurs(on day: Date, anchor: Date, calendar: Calendar = .current) -> Bool {
        let startOfDay = calendar.startOfDay(for: day)
        let anchorDay = calendar.startOfDay(for: anchor)
        guard startOfDay >= anchorDay else { return false }
        switch self {
        case .never:
            return calendar.isDate(day, inSameDayAs: anchor)
        case .daily:
            return true
        case .weekdays:
            return !calendar.isDateInWeekend(day)
        case .weekly:
            return calendar.component(.weekday, from: day) == calendar.component(.weekday, from: anchor)
        case .monthly:
            return calendar.component(.day, from: day) == calendar.component(.day, from: anchor)
        case .yearly:
            return calendar.component(.day, from: day) == calendar.component(.day, from: anchor)
                && calendar.component(.month, from: day) == calendar.component(.month, from: anchor)
        }
    }
}

// MARK: - Delivery

enum Delivery: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    /// Scheduled Live Activity on the Lock Screen and Dynamic Island.
    case live
    /// A time-sensitive notification.
    case nudge
    /// An AlarmKit alarm that breaks through Silent mode and Focus.
    case ring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live Activity"
        case .nudge: "Notification"
        case .ring: "Alarm"
        }
    }

    var subtitle: String {
        switch self {
        case .live: "Arrives on your Lock Screen and Dynamic Island, counting down."
        case .nudge: "A quiet, time-sensitive banner."
        case .ring: "Rings through Silent mode and Focus. For the can't-miss."
        }
    }

    var symbol: String {
        switch self {
        case .live: "capsule.inset.filled"
        case .nudge: "bell"
        case .ring: "alarm"
        }
    }
}

// MARK: - Symbols

enum SymbolCatalog {
    /// Curated set offered in the picker. Order matters: it's the visual order.
    static let all: [String] = [
        "sparkle", "phone", "message", "cart", "pills", "heart",
        "figure.run", "briefcase", "person.2", "book", "airplane", "house",
        "leaf", "fork.knife", "creditcard", "gift", "pawprint", "drop",
        "car", "graduationcap", "envelope", "bed.double", "cup.and.saucer", "trash",
    ]

    /// Lightweight keyword → symbol guess. Used by the wizard and as a fallback for the parser.
    static func guess(for text: String) -> String {
        let lowered = text.lowercased()
        for (keywords, symbol) in keywordMap where keywords.contains(where: { lowered.contains($0) }) {
            return symbol
        }
        return "sparkle"
    }

    private static let keywordMap: [([String], String)] = [
        (["call", "phone", "ring "], "phone"),
        (["text", "message", "reply", "dm ", "whatsapp", "slack"], "message"),
        (["email", "mail", "inbox"], "envelope"),
        (["buy", "groceries", "grocery", "shop", "order", "pick up", "milk"], "cart"),
        (["pill", "meds", "medication", "medicine", "vitamin", "dose"], "pills"),
        (["doctor", "dentist", "therapy", "health", "checkup"], "heart"),
        (["run", "gym", "workout", "yoga", "walk", "stretch", "exercise", "swim"], "figure.run"),
        (["meeting", "standup", "work", "deadline", "submit", "report", "deck", "invoice"], "briefcase"),
        (["birthday", "gift", "anniversary", "present"], "gift"),
        (["flight", "airport", "trip", "pack", "travel", "passport"], "airplane"),
        (["read", "study", "homework", "exam", "class", "book"], "book"),
        (["plant", "water the", "garden"], "leaf"),
        (["dinner", "lunch", "breakfast", "cook", "eat", "recipe"], "fork.knife"),
        (["pay", "rent", "bill", "bank", "tax", "card"], "creditcard"),
        (["dog", "cat", "pet", "vet", "feed"], "pawprint"),
        (["drink water", "hydrate", "water"], "drop"),
        (["car", "oil change", "parking", "fuel", "gas"], "car"),
        (["sleep", "bed", "nap"], "bed.double"),
        (["coffee", "tea"], "cup.and.saucer"),
        (["trash", "garbage", "recycling", "bins"], "trash"),
        (["clean", "laundry", "dishes", "home", "house", "rent"], "house"),
        (["mom", "dad", "friend", "family", "meet", "date"], "person.2"),
        (["school", "university", "course"], "graduationcap"),
    ]
}
