import ActivityKit
import Foundation
import os

private let log = Logger(subsystem: "com.rymynd.app", category: "LiveActivity")

/// Keeps a small, rolling set of Live Activities scheduled for the next reminders.
///
/// iOS 26 lets an app schedule a Live Activity to *start* in the future, even if the app isn't running.
/// Each activity starts `leadMinutes` before its reminder with an alert, counts down, and — because its
/// `staleDate` is the due time — the system re-renders it into its "it's time" form on the dot.
@MainActor
enum LiveActivityScheduler {
    /// Scheduled activities count against the system's simultaneous-activity limit, so keep a few.
    static let capacity = 3

    typealias LiveActivity = Activity<ReminderActivityAttributes>

    static var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private static var managed: [LiveActivity] {
        LiveActivity.activities.filter {
            switch $0.activityState {
            case .active, .pending, .stale: true
            default: false
            }
        }
    }

    /// Returns the reminders that are covered by a Live Activity after reconciliation.
    static func sync(_ reminders: [Reminder], now: Date = .now) async -> Set<UUID> {
        let live = managed
        log.info("sync: enabled=\(isEnabled) existing=\(live.count) reminders=\(reminders.count)")
        guard isEnabled else {
            for activity in live { await activity.end(nil, dismissalPolicy: .immediate) }
            return []
        }

        let existingIDs = Set(live.map(\.attributes.reminderID))
        let chosen = reminders
            .filter { $0.delivery == .live }
            .compactMap { reminder -> (Reminder, Date)? in
                guard let fire = reminder.fireDate else { return nil }
                if fire > now { return (reminder, fire) }
                // Keep showing something that's already due if it's on screen, or only just slipped by.
                let alreadyShown = existingIDs.contains(reminder.id.uuidString)
                let recentlyDue = now.timeIntervalSince(fire) < 60 * 60
                return (alreadyShown && now.timeIntervalSince(fire) < 8 * 3600) || recentlyDue ? (reminder, fire) : nil
            }
            .sorted { $0.1 < $1.1 }
            .prefix(capacity)

        var covered = Set<UUID>()
        for activity in live {
            guard let (reminder, fire) = chosen.first(where: { $0.0.id.uuidString == activity.attributes.reminderID }) else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            let desired = state(for: reminder, fire: fire, now: now, existing: activity.content.state)
            if desired == activity.content.state {
                covered.insert(reminder.id)
            } else if activity.activityState == .pending {
                // A scheduled start can't be moved; replace it.
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.update(ActivityContent(state: desired, staleDate: fire, relevanceScore: relevance(for: fire, now: now)))
                covered.insert(reminder.id)
            }
        }

        for (reminder, fire) in chosen where !covered.contains(reminder.id) {
            if request(reminder, fire: fire, now: now) {
                covered.insert(reminder.id)
            }
        }
        return covered
    }

    /// Flips the activity into its "done" state for a moment before it leaves — the reward on the Lock Screen.
    static func celebrate(reminder: Reminder) async {
        for activity in LiveActivity.activities where activity.attributes.reminderID == reminder.id.uuidString {
            guard activity.activityState == .active || activity.activityState == .stale else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            var state = activity.content.state
            state.stage = .done
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(4)))
        }
    }

    static func end(reminderID: UUID) async {
        for activity in LiveActivity.activities where activity.attributes.reminderID == reminderID.uuidString {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: Helpers

    private static func request(_ reminder: Reminder, fire: Date, now: Date) -> Bool {
        let lead = TimeInterval(Prefs.leadMinutes * 60)
        let start = fire.addingTimeInterval(-lead)
        let attributes = ReminderActivityAttributes(reminderID: reminder.id.uuidString)
        let content = ActivityContent(
            state: state(for: reminder, fire: fire, now: now, existing: nil),
            staleDate: fire,
            relevanceScore: relevance(for: fire, now: now)
        )
        do {
            if start.timeIntervalSince(now) > 5 {
                let body: LocalizedStringResource = Prefs.leadMinutes == 0 ? "It's time." : "In \(Prefs.leadMinutes) minutes."
                let alert = AlertConfiguration(title: "\(reminder.title)", body: body, sound: .default)
                _ = try LiveActivity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil,
                    style: .standard,
                    alertConfiguration: alert,
                    start: start
                )
            } else {
                _ = try LiveActivity.request(attributes: attributes, content: content, pushType: nil)
            }
            log.info("requested activity for \(reminder.title, privacy: .public) start=\(start, privacy: .public)")
            return true
        } catch {
            log.error("request failed for \(reminder.title, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private static func state(
        for reminder: Reminder,
        fire: Date,
        now: Date,
        existing: ReminderActivityAttributes.ContentState?
    ) -> ReminderActivityAttributes.ContentState {
        let windowStart: Date
        if let existing, existing.fireDate == fire {
            windowStart = existing.windowStart
        } else if reminder.isSnoozed {
            windowStart = min(now, fire.addingTimeInterval(-60))
        } else {
            let lead = TimeInterval(max(Prefs.leadMinutes, 1) * 60)
            windowStart = min(max(now, fire.addingTimeInterval(-lead)), fire.addingTimeInterval(-60))
        }
        return .init(
            title: reminder.title,
            note: reminder.notes,
            symbol: reminder.symbol,
            tint: reminder.tint,
            fireDate: fire,
            windowStart: windowStart,
            stage: reminder.isSnoozed ? .snoozed : .upcoming,
            repeatLabel: reminder.repeatRule == .never ? nil : reminder.repeatRule.shortLabel
        )
    }

    private static func relevance(for fire: Date, now: Date) -> Double {
        // Sooner is more relevant; overdue is most relevant.
        let minutes = fire.timeIntervalSince(now) / 60
        return max(0, 100 - minutes / 6)
    }
}
