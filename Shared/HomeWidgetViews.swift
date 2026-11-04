import SwiftUI
import WidgetKit

/// What the Home and Lock Screen widgets show at a moment in time.
struct FeedEntry: TimelineEntry {
    struct Next: Hashable {
        var id: UUID
        var title: String
        var fireDate: Date
    }

    var date: Date
    var next: Next?

    init(date: Date, next: Reminder?) {
        self.date = date
        if let next, let fire = next.fireDate {
            self.next = Next(id: next.id, title: next.title, fireDate: fire)
        }
    }

    static let sample = FeedEntry(date: .now, next: Reminder(title: "Call Mom about the flights", dueDate: .now.addingTimeInterval(40 * 60)))
}

enum WidgetLinks {
    static let type = URL(string: "rymynd://new")!
    static let wizard = URL(string: "rymynd://new/wizard")!
    static func reminder(_ id: UUID) -> URL { URL(string: "rymynd://reminder/\(id.uuidString)")! }
}

private extension Color {
    static let widgetCanvas = Color(red: 0.024, green: 0.027, blue: 0.035)
}

// MARK: - Lock Screen: the line above the clock

/// "Wed 4 Nov · Call Mom about the flights" — or just the date when there's nothing pending.
struct TodayLineView: View {
    let entry: FeedEntry

    var body: some View {
        if let next = entry.next {
            Text("\(ReminderFeed.shortDate(entry.date)) · \(next.title)")
        } else {
            Text(ReminderFeed.shortDate(entry.date))
        }
    }
}

// MARK: - Home Screen: the text box

/// A search-bar-style field. It can't take typing inside a widget, so tapping it opens the app with the keyboard up.
struct ComposePill: View {
    var height: CGFloat = 40
    var showsButton = true

    var body: some View {
        HStack(spacing: 8) {
            Text("Remind me to…")
                .font(.system(size: height * 0.37, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Spacer(minLength: 0)
            if showsButton { PlusDisc(size: height - 10) }
        }
        .padding(.leading, height * 0.4)
        .padding(.trailing, showsButton ? 5 : height * 0.4)
        .frame(height: height)
        .background {
            Capsule()
                .fill(.white.opacity(0.09))
                .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.75) }
        }
    }
}

struct PlusDisc: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background(Circle().fill(.white))
            .widgetAccentable()
    }
}

struct ComposeWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: FeedEntry
    /// For rendering outside WidgetKit (debug gallery).
    var family: WidgetFamily?

    var body: some View {
        switch family ?? environmentFamily {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("rymynd")
                        .font(.system(size: 19, weight: .bold))
                        .tracking(-0.9)
                        .foregroundStyle(.white)
                    Text(ReminderFeed.shortDate(entry.date).uppercased())
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                }
                Spacer(minLength: 0)
                PlusDisc(size: 30)
            }
            Spacer(minLength: 0)
            ComposePill(height: 38, showsButton: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(WidgetLinks.type)
        .containerBackground(Color.widgetCanvas, for: .widget)
    }

    private var medium: some View {
        VStack(spacing: 10) {
            Link(destination: WidgetLinks.type) {
                ComposePill(height: 46)
            }
            HStack(spacing: 10) {
                if let next = entry.next {
                    Link(destination: WidgetLinks.reminder(next.id)) {
                        tile(eyebrow: next.fireDate <= entry.date ? "It's time" : "Next up",
                             title: next.title,
                             detail: timeLabel(next.fireDate),
                             signal: next.fireDate <= entry.date)
                    }
                } else {
                    tile(eyebrow: "Next up", title: "Nothing pending", detail: ReminderFeed.shortDate(entry.date))
                }
                Link(destination: WidgetLinks.wizard) {
                    tile(eyebrow: "Step by step", title: "New reminder", detail: "Use the wizard")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(Color.widgetCanvas, for: .widget)
    }

    private func tile(eyebrow: String, title: String, detail: String, signal: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow.uppercased())
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(signal ? Color(red: 1.0, green: 0.43, blue: 0.25) : .white.opacity(0.42))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.75) }
        }
    }

    private func timeLabel(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: entry.date) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: entry.date), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow \(time)"
        }
        return "\(ReminderFeed.shortDate(date)) \(time)"
    }
}
