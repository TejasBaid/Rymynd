import AppIntents
import SwiftUI

// Live Activity building blocks. They live in the shared layer so the app can render the *real*
// Lock Screen design (in onboarding) rather than an approximation of it.

extension ClosedRange where Bound == Date {
    /// A safe countdown range: never inverted, even once the moment has passed.
    static func countdown(from start: Date = .now, to end: Date) -> ClosedRange<Date> {
        start <= end ? start...end : end...end
    }
}

extension Color {
    static let activityInk = Color(white: 0.07)
}

/// Where a reminder's Live Activity is in its short life.
enum ActivityPhase: Equatable {
    case counting, due, done

    init(state: ReminderActivityAttributes.ContentState, isStale: Bool, now: Date = .now) {
        if state.stage == .done {
            self = .done
        } else if isStale || state.fireDate <= now {
            self = .due
        } else {
            self = .counting
        }
    }

    func eyebrow(snoozed: Bool) -> String {
        switch self {
        case .counting: snoozed ? "SNOOZED" : "COMING UP"
        case .due: "IT'S TIME"
        case .done: "COMPLETED"
        }
    }
}

/// A circular ring that drains toward the moment, with the reminder's symbol inside.
struct ActivityRing: View {
    let start: Date
    let end: Date
    let symbol: String
    let tint: Color
    var size: CGFloat = 44
    var isDue = false
    var onTint: Color = .white

    var body: some View {
        ZStack {
            if isDue {
                Circle().fill(tint)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(onTint)
            } else {
                ProgressView(timerInterval: .countdown(from: start, to: end), countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(tint)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The Lock Screen presentation.
struct ReminderActivityCard: View {
    let state: ReminderActivityAttributes.ContentState
    let reminderID: String
    let phase: ActivityPhase

    var body: some View {
        let tint = state.tint.color

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ActivityRing(
                    start: state.windowStart, end: state.fireDate,
                    symbol: phase == .done ? "checkmark" : state.symbol,
                    tint: tint, size: 48, isDue: phase != .counting, onTint: state.tint.onColor
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(phase.eyebrow(snoozed: state.stage == .snoozed))
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                            .tracking(1)
                            .foregroundStyle(phase == .counting ? Color.white.opacity(0.55) : tint)
                        if let repeatLabel = state.repeatLabel {
                            Text(repeatLabel.uppercased())
                                .font(.system(.caption2, design: .monospaced, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    Text(state.title)
                        .font(.system(.title3, design: .default, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .strikethrough(phase == .done, color: tint)
                    if !state.note.isEmpty, phase != .done {
                        Text(state.note)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 1) {
                    switch phase {
                    case .counting:
                        Text(timerInterval: .countdown(to: state.fireDate), countsDown: true)
                            .font(.system(size: 30, weight: .light))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.white)
                            .frame(width: 92, alignment: .trailing)
                        Text(state.fireDate, style: .time)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.5))
                    case .due:
                        Text("Now")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(tint)
                        Text(state.fireDate, style: .time)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.5))
                    case .done:
                        EmptyView()
                    }
                }
            }

            ActivityActions(state: state, reminderID: reminderID, phase: phase, compact: false)
        }
        .padding(18)
    }
}

/// Done / Snooze, backed by LiveActivityIntents that run in the app's process.
struct ActivityActions: View {
    let state: ReminderActivityAttributes.ContentState
    let reminderID: String
    let phase: ActivityPhase
    let compact: Bool

    private var snoozeMinutes: Int {
        let stored = AppGroup.defaults.integer(forKey: "snoozeMinutes")
        return stored > 0 ? stored : 10
    }

    var body: some View {
        let tint = state.tint.color

        switch phase {
        case .done:
            Text("Cleared.")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white.opacity(0.7))
        case .counting:
            HStack(spacing: 12) {
                ProgressView(timerInterval: .countdown(from: state.windowStart, to: state.fireDate), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(tint)
                Button(intent: CompleteReminderIntent(reminderID: reminderID)) {
                    Label("Done", systemImage: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.14), in: .capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
        case .due:
            HStack(spacing: 10) {
                Button(intent: CompleteReminderIntent(reminderID: reminderID)) {
                    Label("Done", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 9 : 11)
                        .background(tint, in: .capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(state.tint.onColor)

                Button(intent: SnoozeReminderIntent(reminderID: reminderID, minutes: snoozeMinutes)) {
                    Label("\(snoozeMinutes) min", systemImage: "zzz")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 9 : 11)
                        .background(.white.opacity(0.14), in: .capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
        }
    }
}
