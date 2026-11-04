import Foundation

/// An in-progress reminder, shared by the composer, the AI preview and the wizard.
struct ReminderDraft: Equatable {
    var title: String = ""
    var notes: String = ""
    var dueDate: Date?
    /// Further moments for the same reminder ("…and again at 12", "…and the day after").
    /// Each becomes its own reminder, so each gets its own Live Activity, notification or alarm.
    var additionalDates: [Date] = []
    var repeatRule: RepeatRule = .never
    var delivery: Delivery = Prefs.defaultDelivery
    var tint: ReminderTint = .cobalt
    var symbol: String = "sparkle"
    var prompt: String?
    var origin: Reminder.Origin = .wizard

    /// Set by the parser: did the person actually say a time of day?
    var timeIsExplicit = false
    /// Set by the parser: did on-device intelligence shape this draft?
    var usedIntelligence = false

    init() {}

    init(reminder: Reminder) {
        title = reminder.title
        notes = reminder.notes
        dueDate = reminder.dueDate
        repeatRule = reminder.repeatRule
        delivery = reminder.delivery
        tint = reminder.tint
        symbol = reminder.symbol
        prompt = reminder.prompt
        origin = reminder.origin
        timeIsExplicit = true
    }

    /// Every moment, soonest first.
    var allDates: [Date] {
        guard let dueDate else { return [] }
        return ([dueDate] + additionalDates).sorted()
    }

    /// Adds a moment, ignoring duplicates (to the minute).
    mutating func addDate(_ date: Date) {
        let rounded = date.roundedToMinute
        guard dueDate?.roundedToMinute != rounded, !additionalDates.contains(where: { $0.roundedToMinute == rounded }) else { return }
        if dueDate == nil { dueDate = rounded } else { additionalDates.append(rounded) }
        additionalDates.sort()
    }

    /// One reminder per moment. When editing, the first moment updates the existing reminder.
    func makeReminders(updating base: Reminder? = nil) -> [Reminder] {
        let primary = makeReminder(updating: base)
        let extras = additionalDates.map { date -> Reminder in
            var copy = ReminderDraft(copying: self)
            copy.dueDate = date
            return copy.makeReminder()
        }
        return [primary] + extras
    }

    private init(copying other: ReminderDraft) {
        self = other
        additionalDates = []
    }

    var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Builds a new reminder, or applies the draft on top of an existing one when editing.
    func makeReminder(updating base: Reminder? = nil) -> Reminder {
        var reminder = base ?? Reminder(title: title)
        reminder.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if reminder.dueDate != dueDate { reminder.snoozedUntil = nil }
        reminder.dueDate = dueDate?.roundedToMinute
        reminder.repeatRule = dueDate == nil ? .never : repeatRule
        reminder.delivery = delivery
        reminder.tint = tint
        reminder.symbol = symbol
        if base == nil {
            reminder.origin = origin
            reminder.prompt = prompt
        }
        return reminder
    }
}
