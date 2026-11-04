import SwiftUI

struct ReminderRow: View {
    enum TimeStyle { case time, dayTime, date, overdue, none }

    let reminder: Reminder
    let now: Date
    let style: TimeStyle
    var highlighted: Bool
    var showsDivider = true
    /// While a new reminder's title is in flight, its row waits with an empty title slot.
    var isLanding = false
    var onLandingFrame: (CGRect) -> Void = { _ in }
    let onComplete: () -> Void
    let onOpen: () -> Void

    @State private var checked = false
    @State private var strike: Double = 0
    @State private var landed = false

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            CompletionCircle(isDone: checked, tint: reminder.tint, size: 24) {
                guard !checked else { return }
                checked = true
                withAnimation(.easeOut(duration: 0.38).delay(0.08)) { strike = 1 }
                onComplete()
            }
            .padding(.leading, -10)

            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(checked ? Color.ink2 : Color.ink)
                    .textRenderer(StrikeRenderer(progress: strike, color: .ink2))
                    .lineLimit(2)
                    .opacity(isLanding ? 0 : 1)
                    .shimmer(landed)
                    .onGeometryChange(for: CGRect?.self) { isLanding ? $0.frame(in: .global) : nil } action: { frame in
                        if let frame { onLandingFrame(frame) }
                    }
                    .onChange(of: isLanding) { wasLanding, nowLanding in
                        guard wasLanding, !nowLanding else { return }
                        landed = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.9))
                            landed = false
                        }
                    }
                if hasMeta { meta }
            }

            Spacer(minLength: 12)

            if let label = timeLabel {
                Text(label)
                    .font(.mono(.subheadline, weight: .regular))
                    .foregroundStyle(style == .overdue ? ReminderTint.signal.color : Color.ink2)
                    .contentTransition(.numericText())
            }
        }
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(reminder.tint.color.opacity(highlighted ? 0.14 : 0))
                .padding(.horizontal, -10)
        }
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(Color.hairline).frame(height: 0.5).padding(.leading, 34)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
        .animation(Motion.smooth, value: highlighted)
        .onChange(of: reminder.dueDate) { _, _ in
            // A repeating reminder rolled forward: reset for its next life.
            withAnimation(Motion.smooth) {
                checked = false
                strike = 0
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Done", onComplete)
    }

    private var hasMeta: Bool {
        reminder.repeatRule != .never || reminder.isSnoozed || reminder.delivery == .ring || !reminder.notes.isEmpty
    }

    private var meta: some View {
        HStack(spacing: 8) {
            if reminder.repeatRule != .never {
                MetaChip(systemImage: "repeat", text: reminder.repeatRule.shortLabel)
            }
            if reminder.isSnoozed {
                MetaChip(systemImage: "zzz", text: "Snoozed")
            }
            if reminder.delivery == .ring {
                MetaChip(systemImage: "alarm", text: "Alarm")
            }
            if !reminder.notes.isEmpty {
                Text(reminder.notes).lineLimit(1)
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.ink2)
    }

    private var timeLabel: String? {
        guard let fire = reminder.fireDate else { return nil }
        switch style {
        case .time: return TimeFormat.time(fire)
        case .dayTime: return fire.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        case .date: return fire.formatted(.dateTime.day().month(.abbreviated))
        case .overdue: return TimeFormat.relative(fire, now: now)
        case .none: return nil
        }
    }
}

struct DoneRow: View {
    let record: CompletionRecord
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            CompletionCircle(isDone: true, tint: .steel, size: 24, action: onUndo)
                .padding(.leading, -10)
                .accessibilityLabel("Undo")
            Text(record.snapshot.title)
                .font(.body)
                .foregroundStyle(Color.ink3)
                .textRenderer(StrikeRenderer(progress: 1, color: .ink3))
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(TimeFormat.time(record.completedAt))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.ink3)
        }
        .padding(.vertical, 6)
    }
}
