import Foundation

/// Read-only access to the app's saved reminders, for widgets. The app owns writing (see `ReminderStore`).
enum ReminderFeed {
    static let fileURL = AppGroup.containerURL.appending(path: "rymynd-store.json")

    private struct File: Decodable {
        var reminders: [Reminder]
    }

    static func pending() -> [Reminder] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(File.self, from: data))?.reminders ?? []
    }

    /// The reminder that's next in line: the most overdue, else the soonest upcoming. Undated ones never qualify.
    static func next(in reminders: [Reminder]? = nil) -> Reminder? {
        (reminders ?? pending())
            .filter { $0.fireDate != nil }
            .min { $0.fireDate! < $1.fireDate! }
    }

    /// "Wed 4 Nov".
    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }
}
