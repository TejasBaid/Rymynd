import AlarmKit
import SwiftUI

/// Schedules AlarmKit alarms for "Ring" reminders. The system owns the alert; snoozing uses AlarmKit's
/// post-alert countdown, which surfaces as our own Live Activity (see `AlarmLiveActivity` in the widget).
@MainActor
enum AlarmScheduler {
    private static var invalidated = Set<UUID>()

    static var authorization: AlarmManager.AuthorizationState {
        AlarmManager.shared.authorizationState
    }

    static func requestAuthorization() async -> Bool {
        (try? await AlarmManager.shared.requestAuthorization()) == .authorized
    }

    /// Marks an alarm as needing to be rebuilt on the next sync (title, tint or time changed).
    static func invalidate(id: UUID) {
        invalidated.insert(id)
    }

    static func sync(_ reminders: [Reminder], now: Date = .now) async -> Set<UUID> {
        guard authorization == .authorized else { return [] }
        let manager = AlarmManager.shared

        var wanted: [UUID: (Reminder, Date)] = [:]
        for reminder in reminders where reminder.delivery == .ring {
            if let fire = reminder.fireDate, fire > now { wanted[reminder.id] = (reminder, fire) }
        }

        var covered = Set<UUID>()
        let existing = (try? manager.alarms) ?? []
        for alarm in existing {
            guard let (_, fire) = wanted[alarm.id], !invalidated.contains(alarm.id) else {
                // Gone, completed, or edited: clear it (a fresh one is scheduled below if still wanted).
                try? manager.cancel(id: alarm.id)
                continue
            }
            if alarm.state != .scheduled {
                covered.insert(alarm.id) // Ringing or snoozing right now — leave it be.
                continue
            }
            if case .fixed(let date)? = alarm.schedule, abs(date.timeIntervalSince(fire)) < 1 {
                covered.insert(alarm.id)
            } else {
                try? manager.cancel(id: alarm.id)
            }
        }

        for (id, (reminder, fire)) in wanted where !covered.contains(id) {
            do {
                _ = try await manager.schedule(id: id, configuration: configuration(for: reminder, fire: fire))
                covered.insert(id)
            } catch {
                // Falls back to a notification.
            }
        }
        invalidated.removeAll()
        return covered
    }

    private static func configuration(for reminder: Reminder, fire: Date) -> AlarmManager.AlarmConfiguration<ReminderAlarmMetadata> {
        let snooze = AlarmButton(text: "Snooze", textColor: reminder.tint.color, systemImageName: "zzz")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: "\(reminder.title)", secondaryButton: snooze, secondaryButtonBehavior: .countdown)
        } else {
            alert = AlarmPresentation.Alert(
                title: "\(reminder.title)",
                stopButton: AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark"),
                secondaryButton: snooze,
                secondaryButtonBehavior: .countdown
            )
        }
        let presentation = AlarmPresentation(
            alert: alert,
            countdown: AlarmPresentation.Countdown(
                title: "\(reminder.title)",
                pauseButton: AlarmButton(text: "Pause", textColor: reminder.tint.color, systemImageName: "pause.fill")
            ),
            paused: AlarmPresentation.Paused(
                title: "Paused",
                resumeButton: AlarmButton(text: "Resume", textColor: reminder.tint.color, systemImageName: "play.fill")
            )
        )
        let metadata = ReminderAlarmMetadata(
            reminderID: reminder.id.uuidString,
            title: reminder.title,
            symbol: reminder.symbol,
            tint: reminder.tint
        )
        let attributes = AlarmAttributes(presentation: presentation, metadata: metadata, tintColor: reminder.tint.color)
        return AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(Prefs.snoozeMinutes * 60)),
            schedule: .fixed(fire),
            attributes: attributes,
            stopIntent: CompleteReminderIntent(reminderID: reminder.id.uuidString),
            secondaryIntent: nil,
            sound: .default
        )
    }
}
