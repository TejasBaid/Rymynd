import Foundation
import Observation
import WidgetKit

/// The single source of truth. Lives on the main actor; persists to JSON in the App Group container
/// and asks the delivery coordinator to reconcile notifications, Live Activities and alarms after every change.
@MainActor
@Observable
final class ReminderStore {
    static let shared = ReminderStore()

    private(set) var reminders: [Reminder] = []
    private(set) var completions: [CompletionRecord] = []

    /// Set when a reminder is created, so views can celebrate it once.
    var lastCreatedID: UUID?

    @ObservationIgnored private let fileURL = ReminderFeed.fileURL
    @ObservationIgnored private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    @ObservationIgnored private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {
        load()
    }

    // MARK: Queries

    func reminder(id: UUID) -> Reminder? {
        reminders.first { $0.id == id }
    }

    /// Pending reminders, soonest first; undated ("someday") ones last.
    var ordered: [Reminder] {
        reminders.sorted(by: Self.order)
    }

    /// The reminder that deserves the hero spot: the most overdue, else the next upcoming.
    func nextUp(now: Date = .now) -> Reminder? {
        ordered.first { $0.fireDate != nil }
    }

    func completedToday(now: Date = .now) -> [CompletionRecord] {
        completions
            .filter { Calendar.current.isDate($0.completedAt, inSameDayAs: now) }
            .sorted { $0.completedAt > $1.completedAt }
    }

    /// Consecutive days (ending today or yesterday) with at least one completion.
    func streak(now: Date = .now) -> Int {
        let calendar = Calendar.current
        let days = Set(completions.map { calendar.startOfDay(for: $0.completedAt) })
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor), days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    static func order(_ lhs: Reminder, _ rhs: Reminder) -> Bool {
        switch (lhs.fireDate, rhs.fireDate) {
        case let (l?, r?): return l == r ? lhs.createdAt < rhs.createdAt : l < r
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return lhs.createdAt > rhs.createdAt
        }
    }

    // MARK: Mutations

    func add(_ reminder: Reminder) {
        var reminder = reminder
        reminder.title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reminder.title.isEmpty else { return }
        reminders.append(reminder)
        lastCreatedID = reminder.id
        persist()
    }

    /// Adds several reminders at once (a multi-time reminder). The first is the one celebrated.
    func add(contentsOf newReminders: [Reminder]) {
        let valid = newReminders
            .map { reminder -> Reminder in
                var reminder = reminder
                reminder.title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return reminder
            }
            .filter { !$0.title.isEmpty }
        guard let first = valid.first else { return }
        reminders.append(contentsOf: valid)
        lastCreatedID = first.id
        persist()
    }

    func update(_ reminder: Reminder) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        let previous = reminders[index]
        reminders[index] = reminder
        if previous.delivery == .ring || reminder.delivery == .ring {
            AlarmScheduler.invalidate(id: reminder.id)
        }
        persist()
    }

    @discardableResult
    func delete(id: UUID) -> Reminder? {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = reminders.remove(at: index)
        AlarmScheduler.invalidate(id: id)
        persist()
        return removed
    }

    /// Completes the current occurrence. Repeating reminders roll forward; one-offs leave the list.
    @discardableResult
    func complete(id: UUID, at now: Date = .now) -> CompletionRecord? {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return nil }
        let snapshot = reminders[index]
        let record = CompletionRecord(snapshot: snapshot, completedAt: now)
        completions.append(record)

        if snapshot.repeatRule != .never, let anchor = snapshot.dueDate,
           let next = snapshot.repeatRule.occurrence(from: anchor, after: max(now, anchor)) {
            reminders[index].dueDate = next
            reminders[index].snoozedUntil = nil
            reminders[index].completionCount += 1
        } else {
            reminders.remove(at: index)
        }
        AlarmScheduler.invalidate(id: id)
        pruneHistory(now: now)
        persist()
        return record
    }

    func undo(_ record: CompletionRecord) {
        completions.removeAll { $0.id == record.id }
        if let index = reminders.firstIndex(where: { $0.id == record.snapshot.id }) {
            reminders[index] = record.snapshot
        } else {
            reminders.append(record.snapshot)
        }
        AlarmScheduler.invalidate(id: record.snapshot.id)
        persist()
    }

    func snooze(id: UUID, minutes: Int, now: Date = .now) {
        guard let reminder = reminder(id: id) else { return }
        // Snoozing something already due counts from now; snoozing something upcoming pushes it back.
        let from = reminder.isOverdue(at: now) ? now : max(now, reminder.fireDate ?? now)
        snooze(id: id, until: from.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    func snooze(id: UUID, until date: Date) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].snoozedUntil = date.roundedToMinute
        AlarmScheduler.invalidate(id: id)
        persist()
    }

    func restore(_ reminder: Reminder) {
        guard !reminders.contains(where: { $0.id == reminder.id }) else { return }
        reminders.append(reminder)
        persist()
    }

    #if DEBUG
    func replaceAll(with reminders: [Reminder], completions: [CompletionRecord]) {
        self.reminders = reminders
        self.completions = completions
        persist()
    }
    #endif

    func clearHistory() {
        completions.removeAll()
        persist()
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var reminders: [Reminder]
        var completions: [CompletionRecord]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(Snapshot.self, from: data) else { return }
        reminders = snapshot.reminders
        completions = snapshot.completions
    }

    private func persist() {
        let snapshot = Snapshot(reminders: reminders, completions: completions)
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: fileURL, options: [.atomic])
        }
        DeliveryCoordinator.shared.setNeedsSync()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func pruneHistory(now: Date) {
        let cutoff = now.addingTimeInterval(-60 * 60 * 24 * 60)
        completions.removeAll { $0.completedAt < cutoff }
    }
}

extension Date {
    var roundedToMinute: Date {
        let seconds = timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 60).rounded(.down) * 60)
    }
}
