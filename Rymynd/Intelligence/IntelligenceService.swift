import Foundation
import FoundationModels
import Observation

/// The shape we ask the on-device model to fill. Property order is generation order, so the title
/// streams first and the preview card can start "writing" immediately.
@Generable(description: "A reminder understood from a short note someone typed")
struct GeneratedReminder {
    @Guide(description: "What to do, as a short natural phrase of 2 to 7 words in the person's own wording, first letter capitalized. Never include dates, times, repetition or words like 'remind me'. Example: 'Call Mom about the flights'.")
    var title: String

    @Guide(description: "The exact words that describe when, copied from the note, such as 'tomorrow at 6pm', 'in 20 minutes', 'every Monday'. Empty if no timing was mentioned.")
    var timing: String

    @Guide(description: "For timing relative to now such as 'in 20 minutes' or 'in 2 hours': the number of minutes from now. Otherwise 0.", .range(0...525_600))
    var minutesFromNow: Int

    @Guide(description: "Days from today for the date: 0 is today, 1 is tomorrow. -1 if no day was mentioned.", .range(-1...366))
    var dayOffset: Int

    @Guide(description: "Hour on a 24-hour clock. 'morning' is 9, 'noon' is 12, 'afternoon' is 15, 'evening' and 'tonight' are 19. -1 if no time of day was mentioned.", .range(-1...23))
    var hour: Int

    @Guide(description: "Minute of the hour, 0 if not mentioned.", .range(0...59))
    var minute: Int

    @Guide(description: "Only when the person wants to be reminded more than once, such as 'and again at 12' or 'and the day after as well': each additional moment after the first. Empty when there is only one.", .maximumCount(5))
    var alsoAt: [Moment]

    @Guide(description: "How often it repeats. Use never unless the note says every, daily, weekly, each and so on.")
    var repetition: Repetition

    @Guide(description: "The kind of task, used to choose an icon.")
    var kind: Kind

    @Guide(description: "urgent only if the person stressed it must not be missed, such as 'don't let me forget', 'important', medication or a flight. low for casual, someday things. Otherwise normal.")
    var importance: Importance

    @Guide(description: "Any useful extra detail that isn't already in the title, as a short phrase. Empty if none.")
    var detail: String

    @Generable
    struct Moment {
        @Guide(description: "Days from today: 0 is today, 1 is tomorrow, 2 is the day after tomorrow. -1 for the same day as the first moment.", .range(-1...366))
        var dayOffset: Int
        @Guide(description: "Hour on a 24-hour clock, or -1 for the same time as the first moment.", .range(-1...23))
        var hour: Int
        @Guide(.range(0...59))
        var minute: Int
    }

    @Generable
    enum Repetition {
        case never, daily, weekdays, weekly, monthly, yearly
    }

    @Generable
    enum Kind {
        case call, message, email, shopping, medication, health, fitness, work, birthday, travel, study
        case plants, food, money, pet, water, car, sleep, coffee, chores, home, people, general
    }

    @Generable
    enum Importance {
        case low, normal, urgent
    }
}

@MainActor
@Observable
final class IntelligenceService {
    static let shared = IntelligenceService()

    enum Status: Equatable {
        case available, notEnabled, notEligible, notReady, off

        var label: String {
            switch self {
            case .available: "On-device intelligence"
            case .notEnabled: "Turn on Apple Intelligence to use this"
            case .notEligible: "Not supported on this iPhone"
            case .notReady: "Model is still downloading"
            case .off: "Off"
            }
        }
    }

    private(set) var status: Status = .notReady

    private init() {
        refresh()
    }

    var isAvailable: Bool { status == .available }

    func refresh() {
        guard Prefs.useIntelligence else {
            status = .off
            return
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            status = .available
        case .unavailable(.appleIntelligenceNotEnabled):
            status = .notEnabled
        case .unavailable(.deviceNotEligible):
            status = .notEligible
        case .unavailable(.modelNotReady):
            status = .notReady
        case .unavailable:
            status = .notReady
        }
    }

    /// Loads the model into memory while the person is still typing.
    func prewarm() {
        guard isAvailable else { return }
        LanguageModelSession(instructions: Self.instructions(now: .now)).prewarm()
    }

    /// Understands a typed note. Streams the title back as it's generated, then returns a resolved draft.
    /// Always succeeds: without the model, or if it declines, the deterministic parser answers.
    func interpret(_ prompt: String, onTitle: @escaping (String) -> Void) async -> ReminderDraft {
        let now = Date.now
        let heuristic = HeuristicParser.parse(prompt, now: now)
        guard isAvailable else { return heuristic.draft }

        let session = LanguageModelSession(instructions: Self.instructions(now: now))
        do {
            let stream = session.streamResponse(
                to: prompt,
                generating: GeneratedReminder.self,
                options: GenerationOptions(temperature: 0.2)
            )
            for try await snapshot in stream {
                if let title = snapshot.content.title, !title.isEmpty {
                    onTitle(title)
                }
            }
            let response = try await stream.collect()
            return merge(response.content, with: heuristic, now: now)
        } catch {
            return heuristic.draft
        }
    }

    // MARK: - Merge

    private func merge(_ generated: GeneratedReminder, with heuristic: HeuristicParser.Result, now: Date) -> ReminderDraft {
        var draft = heuristic.draft
        draft.origin = .intelligence
        draft.usedIntelligence = true

        let title = generated.title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if !title.isEmpty { draft.title = title.capitalizedFirst }
        let detail = generated.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep a note only if it adds something: not a restatement of the title or the timing.
        let lowered = detail.lowercased()
        let restatesTiming = lowered.range(of: #"\d|tomorrow|today|tonight|morning|afternoon|evening|again|every|daily|weekly|minute|hour|monday|tuesday|wednesday|thursday|friday|saturday|sunday"#, options: .regularExpression) != nil
        let restatesTitle = lowered.contains(title.lowercased()) || title.lowercased().contains(lowered)
        if !detail.isEmpty, !restatesTiming, !restatesTitle { draft.notes = detail.capitalizedFirst }

        // Dates: the deterministic detector decides the day; the model only fills in what was left vague.
        if heuristic.dateFound, let date = draft.dueDate {
            if !draft.timeIsExplicit, generated.hour >= 0 {
                draft.dueDate = Self.set(hour: generated.hour, minute: generated.minute, on: date, prompt: draft.prompt ?? "", now: now)
            }
        } else {
            draft.dueDate = Self.date(from: generated, prompt: draft.prompt ?? "", now: now)
            draft.timeIsExplicit = generated.hour >= 0 || generated.minutesFromNow > 0
        }

        // More moments: the deterministic parser's are exact; otherwise use the model's.
        if draft.additionalDates.isEmpty, let first = draft.dueDate, !generated.alsoAt.isEmpty {
            let calendar = Calendar.current
            for moment in generated.alsoAt {
                let day = moment.dayOffset >= 0
                    ? calendar.date(byAdding: .day, value: moment.dayOffset, to: calendar.startOfDay(for: now)) ?? first
                    : first
                let hour = moment.hour >= 0 ? moment.hour : calendar.component(.hour, from: first)
                let minute = moment.hour >= 0 ? moment.minute : calendar.component(.minute, from: first)
                guard let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), date > now else { continue }
                draft.addDate(date)
            }
        }

        if draft.repeatRule == .never {
            draft.repeatRule = RepeatRule(generated.repetition)
        }
        if draft.dueDate == nil {
            draft.repeatRule = .never
            draft.additionalDates = []
        }

        let style = generated.kind.style
        draft.symbol = style.symbol
        draft.tint = style.tint

        switch generated.importance {
        case .urgent: draft.delivery = AlarmScheduler.authorization == .authorized ? .ring : .live
        case .low: draft.delivery = .nudge
        case .normal: draft.delivery = Prefs.defaultDelivery
        }
        return draft
    }

    private static func date(from generated: GeneratedReminder, prompt: String, now: Date) -> Date? {
        if generated.minutesFromNow > 0 {
            return now.addingTimeInterval(TimeInterval(generated.minutesFromNow * 60)).roundedToMinute
        }
        guard generated.dayOffset >= 0 || generated.hour >= 0 else { return nil }
        let calendar = Calendar.current
        let dayOffset = max(generated.dayOffset, 0)
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) else { return nil }
        if generated.hour < 0 {
            return HeuristicParser.applyDayPart(prompt.lowercased(), to: day, now: now)
        }
        var date = set(hour: generated.hour, minute: generated.minute, on: day, prompt: prompt, now: now)
        if date <= now, dayOffset == 0 {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }

    private static func set(hour: Int, minute: Int, on day: Date, prompt: String, now: Date) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        return HeuristicParser.fixMeridiem(base, phrase: prompt.lowercased())
    }

    private static func instructions(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, d MMMM yyyy 'at' HH:mm"
        return """
        You turn quick notes into reminders. It is currently \(formatter.string(from: now)).
        Work out what the person wants to be reminded about and when. Keep the title short and in their words, \
        without any timing. Never invent a time that wasn't mentioned. \
        If they ask for more than one moment, the first goes in dayOffset, hour and minute, and the rest in alsoAt.
        """
    }
}

// MARK: - Mappings

extension RepeatRule {
    init(_ repetition: GeneratedReminder.Repetition) {
        switch repetition {
        case .never: self = .never
        case .daily: self = .daily
        case .weekdays: self = .weekdays
        case .weekly: self = .weekly
        case .monthly: self = .monthly
        case .yearly: self = .yearly
        }
    }
}

extension GeneratedReminder.Kind {
    var style: (symbol: String, tint: ReminderTint) {
        switch self {
        case .call: ("phone", .cobalt)
        case .message: ("message", .cobalt)
        case .email: ("envelope", .cobalt)
        case .shopping: ("cart", .volt)
        case .medication: ("pills", .mint)
        case .health: ("heart", .mint)
        case .fitness: ("figure.run", .mint)
        case .work: ("briefcase", .violet)
        case .birthday: ("gift", .violet)
        case .travel: ("airplane", .ice)
        case .study: ("book", .violet)
        case .plants: ("leaf", .mint)
        case .food: ("fork.knife", .volt)
        case .money: ("creditcard", .steel)
        case .pet: ("pawprint", .volt)
        case .water: ("drop", .ice)
        case .car: ("car", .steel)
        case .sleep: ("bed.double", .ice)
        case .coffee: ("cup.and.saucer", .volt)
        case .chores: ("trash", .steel)
        case .home: ("house", .mint)
        case .people: ("person.2", .cobalt)
        case .general: ("sparkle", .cobalt)
        }
    }
}
