import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

/// The Live Activity AlarmKit shows while a "Ring" reminder is snoozed (counting down) or paused.
/// The ringing alert itself is drawn by the system.
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<ReminderAlarmMetadata>.self) { context in
            AlarmLockScreenView(context: context)
                .activityBackgroundTint(Color.activityInk.opacity(0.82))
                .activitySystemActionForegroundColor(context.attributes.tintColor)
        } dynamicIsland: { context in
            let tint = context.attributes.tintColor
            let symbol = context.attributes.metadata?.symbol ?? "alarm"
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(tint, in: .circle)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AlarmTimeText(mode: context.state.mode, tint: tint, size: 26)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(modeLabel(context.state.mode))
                            .font(.caption2.weight(.semibold))
                            .tracking(1.2)
                            .foregroundStyle(tint)
                        Text(context.attributes.metadata?.title ?? "Reminder")
                            .font(.system(.headline, design: .default, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AlarmDoneButton(context: context)
                        .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
            } compactTrailing: {
                AlarmTimeText(mode: context.state.mode, tint: tint, size: 14)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }
}

private func modeLabel(_ mode: AlarmPresentationState.Mode) -> String {
    switch mode {
    case .countdown: "SNOOZED · RINGS AGAIN IN"
    case .paused: "PAUSED"
    case .alert: "RINGING"
    @unknown default: "ALARM"
    }
}

private struct AlarmTimeText: View {
    let mode: AlarmPresentationState.Mode
    let tint: Color
    let size: CGFloat

    var body: some View {
        Group {
            switch mode {
            case .countdown(let countdown):
                Text(timerInterval: .countdown(to: countdown.fireDate), countsDown: true)
            case .paused(let paused):
                let remaining = max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
                Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
            case .alert:
                Text("Now")
            @unknown default:
                Text("")
            }
        }
        .font(.system(size: size, weight: .semibold, design: .default))
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .foregroundStyle(tint)
    }
}

private struct AlarmDoneButton: View {
    let context: ActivityViewContext<AlarmAttributes<ReminderAlarmMetadata>>

    var body: some View {
        if let id = context.attributes.metadata?.reminderID {
            Button(intent: CompleteReminderIntent(reminderID: id)) {
                Label("Done", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(context.attributes.tintColor, in: .capsule)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
    }
}

struct AlarmLockScreenView: View {
    let context: ActivityViewContext<AlarmAttributes<ReminderAlarmMetadata>>

    var body: some View {
        let tint = context.attributes.tintColor
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: context.attributes.metadata?.symbol ?? "alarm")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(tint, in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(modeLabel(context.state.mode))
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(tint)
                    Text(context.attributes.metadata?.title ?? "Reminder")
                        .font(.system(.title3, design: .default, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                AlarmTimeText(mode: context.state.mode, tint: .white, size: 30)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            AlarmDoneButton(context: context)
        }
        .padding(18)
    }
}
