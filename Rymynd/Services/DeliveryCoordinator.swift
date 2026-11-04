import Foundation

/// Reconciles the store with the three ways a reminder can reach you:
/// AlarmKit alarms, scheduled Live Activities, and local notifications (as primary or as backup).
@MainActor
final class DeliveryCoordinator {
    static let shared = DeliveryCoordinator()

    private var debounce: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?

    func setNeedsSync() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Runs a full reconciliation, serialised behind any sync already in flight.
    func syncNow() async {
        let previous = inFlight
        let task = Task { @MainActor in
            await previous?.value
            await Self.reconcile()
        }
        inFlight = task
        await task.value
    }

    private static func reconcile() async {
        let reminders = ReminderStore.shared.reminders
        let alarms = await AlarmScheduler.sync(reminders)
        let live = await LiveActivityScheduler.sync(reminders)
        await NotificationScheduler.sync(reminders, liveCovered: live, alarmCovered: alarms)
    }
}

/// Entry points shared by the UI, notification actions, and Live Activity / alarm intents.
@MainActor
enum ReminderActions {
    enum Origin { case app, liveActivity, notification }

    static func complete(id: UUID, origin: Origin) async {
        let store = ReminderStore.shared
        if let reminder = store.reminder(id: id) {
            store.complete(id: id)
            await LiveActivityScheduler.celebrate(reminder: reminder)
        } else {
            await LiveActivityScheduler.end(reminderID: id)
        }
        NotificationScheduler.clearDelivered(for: id)
        await DeliveryCoordinator.shared.syncNow()
    }

    /// Follow-up for completions that happened in the UI (where the store mutation is animated by the view).
    static func didComplete(_ reminder: Reminder) async {
        await LiveActivityScheduler.celebrate(reminder: reminder)
        NotificationScheduler.clearDelivered(for: reminder.id)
    }

    static func snooze(id: UUID, minutes: Int, origin: Origin) async {
        ReminderStore.shared.snooze(id: id, minutes: minutes)
        NotificationScheduler.clearDelivered(for: id)
        await DeliveryCoordinator.shared.syncNow()
    }
}
