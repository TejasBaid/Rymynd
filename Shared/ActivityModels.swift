import ActivityKit
import AlarmKit
import Foundation

// MARK: - Live Activity

struct ReminderActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var note: String
        var symbol: String
        var tint: ReminderTint
        /// When the reminder is due. The activity's `staleDate` is set to this, so the
        /// system re-renders it into its "it's time" form without the app running.
        var fireDate: Date
        /// Beginning of the countdown window, for progress.
        var windowStart: Date
        var stage: Stage
        var repeatLabel: String?

        enum Stage: String, Codable, Hashable {
            case upcoming
            case snoozed
            case done
        }
    }

    var reminderID: String
}

// MARK: - Alarm

/// Metadata carried by AlarmKit alarms so the countdown Live Activity can be styled per reminder.
struct ReminderAlarmMetadata: AlarmMetadata {
    var reminderID: String
    var title: String
    var symbol: String
    var tint: ReminderTint
}

// MARK: - App Group

enum AppGroup {
    static let identifier = "group.com.rymynd.app"

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        let fallback = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
