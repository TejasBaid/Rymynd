import AppIntents
import Foundation

// These intents back the buttons inside the Live Activity and the AlarmKit alert.
// The file is compiled into both targets so the widget can reference the types, but
// LiveActivityIntents always execute in the app's process — only the app target does work.

struct CompleteReminderIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Complete Reminder"
    static let isDiscoverable = false

    @Parameter(title: "Reminder ID")
    var reminderID: String

    init() {}

    init(reminderID: String) {
        self.reminderID = reminderID
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        if let id = UUID(uuidString: reminderID) {
            await ReminderActions.complete(id: id, origin: .liveActivity)
        }
        #endif
        return .result()
    }
}

struct SnoozeReminderIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Snooze Reminder"
    static let isDiscoverable = false

    @Parameter(title: "Reminder ID")
    var reminderID: String

    @Parameter(title: "Minutes")
    var minutes: Int

    init() {}

    init(reminderID: String, minutes: Int) {
        self.reminderID = reminderID
        self.minutes = minutes
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        if let id = UUID(uuidString: reminderID) {
            await ReminderActions.snooze(id: id, minutes: minutes, origin: .liveActivity)
        }
        #endif
        return .result()
    }
}
