import SwiftUI

/// The hero: one reminder on a slab of Liquid Glass, read like an instrument.
struct NextUpCard: View {
    let reminder: Reminder?
    let now: Date
    let doneToday: Int
    let hasAnything: Bool
    let ripple: Int
    let onComplete: () -> Void
    let onOpen: () -> Void
    let onSnooze: () -> Void
    var landingID: UUID?
    var onLandingFrame: (CGRect) -> Void = { _ in }

    @State private var completedID: UUID?
    @State private var circleCenter: CGPoint = .zero

    private var tint: ReminderTint {
        guard let reminder else { return doneToday > 0 ? .mint : .cobalt }
        return reminder.isOverdue(at: now) ? .signal : reminder.tint
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let reminder {
                filled(reminder)
                    .id(reminder.id)
                    .transition(.softBlur)
            } else {
                EmptyHeroContent(doneToday: doneToday, hasAnything: hasAnything)
                    .transition(.softBlur)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(.named("hero"))
        // The ripple distorts the content only; the glass beneath stays crisp.
        .ripple(at: circleCenter, trigger: ripple, amplitude: 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 32, style: .continuous))
        .animation(Motion.smooth, value: reminder?.id)
        .contentShape(.rect(cornerRadius: 32))
        .onTapGesture { if reminder != nil { onOpen() } }
        .contextMenu {
            if reminder != nil {
                Button("Done", systemImage: "checkmark.circle", action: complete)
                Button("Snooze \(Prefs.snoozeMinutes) minutes", systemImage: "zzz", action: onSnooze)
                Button("Edit", systemImage: "pencil", action: onOpen)
            }
        }
    }

    private func complete() {
        guard let reminder, completedID != reminder.id else { return }
        completedID = reminder.id
        onComplete()
    }

    @ViewBuilder
    private func filled(_ reminder: Reminder) -> some View {
        let overdue = reminder.isOverdue(at: now)
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Text(overdue ? "It's time" : reminder.isSnoozed ? "Snoozed" : "Next up")
                    .eyebrow(overdue ? tint.color : .ink2)
                Spacer()
                if reminder.repeatRule != .never {
                    MetaChip(systemImage: "repeat", text: reminder.repeatRule.shortLabel)
                }
                Text(reminder.delivery == .live ? "Live" : reminder.delivery == .ring ? "Alarm" : "Notify")
                    .eyebrow(.ink3)
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(reminder.title)
                        .font(.display(size: 28, weight: .semibold))
                        .tracking(-0.7)
                        .foregroundStyle(Color.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                        .textRenderer(StrikeRenderer(progress: completedID == reminder.id ? 1 : 0, color: tint.color, thickness: 2))
                        .animation(.easeOut(duration: 0.4), value: completedID)
                        .opacity(landingID == reminder.id ? 0 : 1)
                        .onGeometryChange(for: CGRect?.self) { landingID == reminder.id ? $0.frame(in: .global) : nil } action: { frame in
                            if let frame { onLandingFrame(frame) }
                        }
                    if !reminder.notes.isEmpty {
                        Text(reminder.notes)
                            .font(.subheadline)
                            .foregroundStyle(Color.ink2)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }

            if let fire = reminder.fireDate {
                HStack(alignment: .bottom) {
                    CountdownDisplay(fire: fire, tint: tint)
                    Spacer()
                    CompletionCircle(isDone: completedID == reminder.id, tint: reminder.tint, size: 38, action: complete)
                        .onGeometryChange(for: CGPoint.self) { proxy in
                            let frame = proxy.frame(in: .named("hero"))
                            return CGPoint(x: frame.midX, y: frame.midY)
                        } action: { circleCenter = $0 }
                }
                TickRail(start: max(reminder.createdAt, fire.addingTimeInterval(-24 * 3600)), fire: fire, tint: tint)
            }
        }
    }
}

// MARK: - Countdown

private struct CountdownDisplay: View {
    let fire: Date
    let tint: ReminderTint

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let remaining = fire.timeIntervalSince(now)
            let (headline, suffix) = parts(remaining: remaining, now: now)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(headline)
                        .font(.system(size: 58, weight: .light))
                        .monospacedDigit()
                        .tracking(-2)
                        .foregroundStyle(remaining <= 0 ? tint.color : Color.ink)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy(duration: 0.35), value: headline)
                    if let suffix {
                        Text(suffix)
                            .font(.mono(.callout, weight: .medium))
                            .foregroundStyle(Color.ink2)
                    }
                }
                Text(caption(remaining: remaining, now: now))
                    .onChange(of: Int(remaining.rounded(.up))) { _, seconds in
                        // The last five seconds tick under your thumb; arrival lands with weight.
                        if (1...5).contains(seconds) { Haptics.shared.play(.tick) }
                        if seconds == 0 { Haptics.shared.play(.arrive) }
                    }
                    .font(.mono(.caption, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.ink2)
                    .contentTransition(.numericText())
            }
        }
    }

    /// Splits "7:30 PM" into a large "7:30" and a small mono "PM".
    private func parts(remaining: TimeInterval, now: Date) -> (String, String?) {
        if remaining <= 0 { return ("Now", nil) }
        if remaining < 3600 { return (TimeFormat.countdown(fire, now: now), nil) }
        let time = TimeFormat.time(fire)
        let pieces = time.split(whereSeparator: { $0 == " " || $0 == "\u{202F}" || $0 == "\u{00A0}" })
        if pieces.count == 2, pieces[1].allSatisfy({ $0.isLetter || $0 == "." }) {
            return (String(pieces[0]), String(pieces[1]).uppercased())
        }
        return (time, nil)
    }

    private func caption(remaining: TimeInterval, now: Date) -> String {
        if remaining <= 0 { return "Due \(TimeFormat.time(fire)) · \(TimeFormat.relative(fire, now: now))" }
        if remaining < 3600 { return "Until \(TimeFormat.time(fire))" }
        if Calendar.current.isDateInToday(fire) { return "Today · \(TimeFormat.relative(fire, now: now))" }
        return "\(TimeFormat.day(fire, now: now)) · \(TimeFormat.relative(fire, now: now))"
    }
}

/// A ruler of hairline ticks. Elapsed time lights up; the present is the tallest, brightest mark.
struct TickRail: View {
    let start: Date
    let fire: Date
    let tint: ReminderTint

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = max(fire.timeIntervalSince(start), 1)
            let progress = min(max(context.date.timeIntervalSince(start) / total, 0), 1)
            Canvas { canvas, size in
                let spacing: CGFloat = 5
                let count = max(Int(size.width / spacing), 2)
                let head = Int((Double(count - 1) * progress).rounded())
                for index in 0..<count {
                    let x = CGFloat(index) * (size.width - 1.5) / CGFloat(count - 1)
                    let major = index.isMultiple(of: 6)
                    let height: CGFloat = index == head ? size.height : major ? size.height * 0.55 : size.height * 0.34
                    let rect = CGRect(x: x, y: size.height - height, width: 1.5, height: height)
                    let elapsed: Color = tint == .signal ? tint.color : .white.opacity(0.62)
                    let color: Color = index == head ? (tint == .signal ? tint.color : .white) : index < head ? elapsed : .white.opacity(major ? 0.2 : 0.1)
                    canvas.fill(Path(roundedRect: rect, cornerRadius: 0.75), with: .color(color))
                }
            }
            .frame(height: 20)
        }
        .accessibilityHidden(true)
    }
}

struct PulseDot: View {
    var color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .background {
                Circle()
                    .fill(color.opacity(0.45))
                    .phaseAnimator([false, true]) { view, expanded in
                        view.scaleEffect(expanded ? 3 : 1).opacity(expanded ? 0 : 0.9)
                    } animation: { expanded in
                        expanded ? .easeOut(duration: 1.6) : .linear(duration: 0.001)
                    }
            }
    }
}

// MARK: - Empty

private struct EmptyHeroContent: View {
    let doneToday: Int
    let hasAnything: Bool
    @State private var appeared = false

    private var symbol: String { doneToday > 0 ? "checkmark.circle" : hasAnything ? "moon" : "circle.dashed" }
    private var title: String { doneToday > 0 ? "All clear." : hasAnything ? "Nothing scheduled." : "Nothing pending." }
    private var message: String {
        if doneToday > 0 { return doneToday == 1 ? "1 done today." : "\(doneToday) done today." }
        if hasAnything { return "Your someday list is below." }
        return "Type it below — “call Mom at 6”, “water plants every Sunday” — and it arrives on time."
    }
    private var tint: ReminderTint { doneToday > 0 ? .mint : .cobalt }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                if appeared {
                    Image(systemName: symbol)
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(tint.color)
                        .transition(.symbolEffect(.drawOn))
                }
            }
            .frame(width: 40, height: 40, alignment: .leading)

            RevealText(text: title, duration: 1.0)
                .font(.display(size: 30, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Color.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).delay(0.2)) { appeared = true }
        }
    }
}
