import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct ReminderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReminderActivityAttributes.self) { context in
            ReminderActivityCard(
                state: context.state,
                reminderID: context.attributes.reminderID,
                phase: ActivityPhase(context: context)
            )
            .activityBackgroundTint(Color.activityInk.opacity(0.82))
            .activitySystemActionForegroundColor(context.state.tint.color)
        } dynamicIsland: { context in
            let state = context.state
            let tint = state.tint.color
            let phase = ActivityPhase(context: context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityRing(
                        start: state.windowStart, end: state.fireDate,
                        symbol: phase == .done ? "checkmark" : state.symbol,
                        tint: tint, size: 44, isDue: phase != .counting, onTint: state.tint.onColor
                    )
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        switch phase {
                        case .counting:
                            Text(timerInterval: .countdown(to: state.fireDate), countsDown: true)
                                .monospacedDigit()
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(tint)
                        case .due:
                            Text("Now").foregroundStyle(tint)
                        case .done:
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(tint)
                        }
                    }
                    .font(.system(size: 24, weight: .semibold, design: .default))
                    .frame(width: 84, height: 44, alignment: .trailing)
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 4) {
                        Text(phase.eyebrow(snoozed: state.stage == .snoozed))
                            .foregroundStyle(phase == .counting ? Color.secondary : tint)
                        if phase != .done {
                            Text("·").foregroundStyle(.tertiary)
                            Text(state.fireDate, style: .time).foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .padding(.top, 14)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(state.title)
                            .font(.system(.title3, design: .default, weight: .semibold))
                            .lineLimit(1)
                            .strikethrough(phase == .done, color: tint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ActivityActions(state: state, reminderID: context.attributes.reminderID, phase: phase, compact: true)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: phase == .done ? "checkmark" : state.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.leading, 2)
            } compactTrailing: {
                Group {
                    switch phase {
                    case .counting:
                        Text(timerInterval: .countdown(to: state.fireDate), countsDown: true)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                    case .due:
                        Text("Now")
                    case .done:
                        Text("Done")
                    }
                }
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundStyle(tint)
                .frame(width: 46, alignment: .trailing)
            } minimal: {
                if phase == .counting {
                    ProgressView(timerInterval: .countdown(from: state.windowStart, to: state.fireDate), countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        Image(systemName: state.symbol)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    .progressViewStyle(.circular)
                    .tint(tint)
                } else {
                    Image(systemName: phase == .done ? "checkmark" : state.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            .keylineTint(tint)
            .widgetURL(URL(string: "rymynd://reminder/\(context.attributes.reminderID)"))
        }
    }
}

extension ActivityPhase {
    init(context: ActivityViewContext<ReminderActivityAttributes>) {
        self.init(state: context.state, isStale: context.isStale)
    }
}

// MARK: - Previews

extension ReminderActivityAttributes {
    fileprivate static var preview: ReminderActivityAttributes {
        ReminderActivityAttributes(reminderID: UUID().uuidString)
    }
}

extension ReminderActivityAttributes.ContentState {
    fileprivate static var counting: Self {
        .init(title: "Call Mom", note: "About the flights", symbol: "phone", tint: .cobalt,
              fireDate: .now.addingTimeInterval(12 * 60), windowStart: .now.addingTimeInterval(-3 * 60),
              stage: .upcoming, repeatLabel: nil)
    }

    fileprivate static var due: Self {
        .init(title: "Take vitamins", note: "", symbol: "pills", tint: .ice,
              fireDate: .now.addingTimeInterval(-60), windowStart: .now.addingTimeInterval(-16 * 60),
              stage: .upcoming, repeatLabel: "Daily")
    }

    fileprivate static var done: Self {
        .init(title: "Water the plants", note: "", symbol: "leaf", tint: .mint,
              fireDate: .now.addingTimeInterval(-60), windowStart: .now.addingTimeInterval(-16 * 60),
              stage: .done, repeatLabel: "Weekly")
    }
}

#Preview("Lock Screen", as: .content, using: ReminderActivityAttributes.preview) {
    ReminderLiveActivity()
} contentStates: {
    ReminderActivityAttributes.ContentState.counting
    ReminderActivityAttributes.ContentState.due
    ReminderActivityAttributes.ContentState.done
}

#Preview("Island", as: .dynamicIsland(.expanded), using: ReminderActivityAttributes.preview) {
    ReminderLiveActivity()
} contentStates: {
    ReminderActivityAttributes.ContentState.counting
    ReminderActivityAttributes.ContentState.due
}
