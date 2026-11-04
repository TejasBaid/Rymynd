import UserNotifications

enum NotificationScheduler {
    static let categoryID = "rymynd.reminder"
    static let idPrefix = "rymynd."

    enum Action {
        static let done = "rymynd.done"
        static let snooze = "rymynd.snooze"
        static let snoozeHour = "rymynd.snooze.hour"
    }

    static func registerCategories() {
        let done = UNNotificationAction(
            identifier: Action.done, title: "Done", options: [],
            icon: UNNotificationActionIcon(systemImageName: "checkmark")
        )
        let snooze = UNNotificationAction(
            identifier: Action.snooze, title: "Snooze \(Prefs.snoozeMinutes) min", options: [],
            icon: UNNotificationActionIcon(systemImageName: "zzz")
        )
        let later = UNNotificationAction(
            identifier: Action.snoozeHour, title: "In an hour", options: [],
            icon: UNNotificationActionIcon(systemImageName: "clock.arrow.circlepath")
        )
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [done, snooze, later],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Rebuilds every pending Rymynd notification from scratch. Cheap: there are never more than a few dozen.
    @MainActor
    static func sync(_ reminders: [Reminder], liveCovered: Set<UUID>, alarmCovered: Set<UUID>, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) })

        let status = await authorizationStatus()
        let overdue = reminders.filter { $0.isOverdue(at: now) }.count
        try? await center.setBadgeCount(overdue)
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let lead = Prefs.leadMinutes
        let notifyAtTime = Prefs.notifyAtTime
        let upcoming = reminders
            .compactMap { reminder -> (Reminder, Date)? in
                guard let fire = reminder.fireDate, fire > now else { return nil }
                return (reminder, fire)
            }
            .sorted { $0.1 < $1.1 }

        var scheduled = 0
        for (reminder, fire) in upcoming where scheduled < 60 {
            let needsNotification: Bool
            switch reminder.delivery {
            case .nudge:
                needsNotification = true
            case .live:
                // The Live Activity's own alert covers "at the moment"; otherwise ping at the time as well.
                needsNotification = !liveCovered.contains(reminder.id) || (lead > 0 && notifyAtTime)
            case .ring:
                needsNotification = !alarmCovered.contains(reminder.id)
            }
            guard needsNotification else { continue }

            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.notes.isEmpty ? bodyLine(for: reminder) : reminder.notes
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = categoryID
            content.threadIdentifier = reminder.id.uuidString
            content.relevanceScore = 1
            content.userInfo = ["reminderID": reminder.id.uuidString]

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = "\(idPrefix)\(reminder.id.uuidString).\(Int(fire.timeIntervalSince1970))"
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            scheduled += 1
        }
    }

    static func clearDelivered(for id: UUID) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let ids = delivered
                .filter { ($0.request.content.userInfo["reminderID"] as? String) == id.uuidString }
                .map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    private static func bodyLine(for reminder: Reminder) -> String {
        if reminder.isSnoozed { return "Snoozed — it's time now." }
        if reminder.repeatRule != .never { return "It's time · \(reminder.repeatRule.label.lowercased())" }
        return "It's time."
    }
}
