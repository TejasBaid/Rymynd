import SwiftUI
import WidgetKit

/// Reads the saved reminders and refreshes when the day changes or the next reminder comes due.
/// The app reloads these timelines whenever reminders change.
struct FeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> FeedEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (FeedEntry) -> Void) {
        let next = ReminderFeed.next()
        completion(context.isPreview && next == nil ? .sample : FeedEntry(date: .now, next: next))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeedEntry>) -> Void) {
        let now = Date.now
        let next = ReminderFeed.next()
        let calendar = Calendar.current
        var moments: [Date] = [now]
        if let fire = next?.fireDate, fire > now { moments.append(fire) }
        var midnight = calendar.startOfDay(for: now)
        for _ in 0..<3 {
            midnight = calendar.date(byAdding: .day, value: 1, to: midnight)!
            moments.append(midnight)
        }
        let entries = moments.sorted().map { FeedEntry(date: $0, next: next) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Sits above the clock on the Lock Screen: the date, then your next reminder.
struct TodayLineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayLine", provider: FeedProvider()) { entry in
            TodayLineView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Date & Next Up")
        .description("The date, followed by your next reminder.")
        .supportedFamilies([.accessoryInline])
    }
}

/// A text box for your Home Screen. Tap it to start typing a reminder.
struct ComposeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Compose", provider: FeedProvider()) { entry in
            ComposeWidgetView(entry: entry)
        }
        .configurationDisplayName("New Reminder")
        .description("Tap the box to type a reminder.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview("Lock Screen", as: .accessoryInline) {
    TodayLineWidget()
} timeline: {
    FeedEntry.sample
    FeedEntry(date: .now, next: nil)
}

#Preview("Small", as: .systemSmall) {
    ComposeWidget()
} timeline: {
    FeedEntry.sample
}

#Preview("Medium", as: .systemMedium) {
    ComposeWidget()
} timeline: {
    FeedEntry.sample
    FeedEntry(date: .now, next: nil)
}
