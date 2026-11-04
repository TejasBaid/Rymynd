import SwiftUI

// MARK: - What

struct WhatStep: View {
    @Bindable var model: WizardModel
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    TextField("Call Mom about the flights", text: $model.draft.title, axis: .vertical)
                        .font(.display(size: 28, weight: .semibold))
                        .tracking(-0.6)
                        .lineLimit(1...4)
                        .focused($titleFocused)
                        .submitLabel(.next)
                        .onSubmit { if model.canAdvance { model.next() } }
                        .padding(.top, 5)
                }
                TextField("Add a note", text: $model.draft.notes, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(Color.ink2)
                    .lineLimit(1...3)
            }
            .onChange(of: model.draft.title) { _, _ in
                withAnimation(Motion.snappy) { model.titleChanged() }
            }

        }
        .onAppear {
            if model.draft.title.isEmpty {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    titleFocused = true
                }
            }
        }
    }
}

// MARK: - When

struct WhenStep: View {
    @Bindable var model: WizardModel
    @State private var showPicker = false

    private struct Option: Identifiable {
        let id: WizardModel.WhenChoice
        let title: String
        let symbol: String
        let date: Date?
    }

    private func options(now: Date) -> [Option] {
        [
            Option(id: .in20, title: "In 20 minutes", symbol: "timer", date: QuickTimes.inMinutes(20, now: now)),
            Option(id: .inHour, title: "In an hour", symbol: "clock", date: QuickTimes.inMinutes(60, now: now)),
            Option(id: .evening, title: "This evening", symbol: "sunset", date: QuickTimes.evening(now: now)),
            Option(id: .tomorrow, title: "Tomorrow morning", symbol: "sunrise", date: QuickTimes.tomorrowMorning(now: now)),
            Option(id: .weekend, title: "This weekend", symbol: "sun.max", date: QuickTimes.weekend(now: now)),
            Option(id: .nextWeek, title: "Next week", symbol: "calendar", date: QuickTimes.nextWeek(now: now)),
        ]
    }

    var body: some View {
        let now = Date.now
        VStack(spacing: 0) {
        VStack(spacing: 0) {
            ForEach(options(now: now)) { option in
                row(option.title, symbol: option.symbol, trailing: option.date.map { label(for: $0, now: now) }, selected: model.whenChoice == option.id) {
                    choose(option.id, date: option.date)
                }
            }
            row("Pick a date & time", symbol: "calendar.badge.clock", trailing: model.whenChoice == .custom ? model.draft.dueDate.map { label(for: $0, now: now) } : nil, selected: model.whenChoice == .custom) {
                if model.draft.dueDate == nil { model.draft.dueDate = QuickTimes.suggested() }
                choose(.custom, date: model.draft.dueDate)
                withAnimation(Motion.smooth) { showPicker = true }
            }
            if showPicker || (model.whenChoice == .custom && model.draft.dueDate != nil) {
                DatePicker(
                    "Date and time",
                    selection: Binding(
                        get: { model.draft.dueDate ?? QuickTimes.suggested() },
                        set: { model.draft.dueDate = $0; model.whenChoice = .custom }
                    ),
                    in: Date.now...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(Color(white: 0.45))
                .padding(.vertical, 8)
                .transition(.softBlur.combined(with: .move(edge: .top)))
            }
            row("No time — someday", symbol: "moon.zzz", trailing: nil, selected: model.whenChoice == WizardModel.WhenChoice.none) {
                choose(.none, date: nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        .haptic(.selection, trigger: model.whenChoice)

        if model.draft.dueDate != nil {
            AlsoAtPanel(draft: $model.draft)
                .padding(.top, 20)
        }
        }
    }

    private func choose(_ choice: WizardModel.WhenChoice, date: Date?) {
        withAnimation(Motion.snappy) {
            model.whenChoice = choice
            model.draft.dueDate = date
            if date == nil { model.draft.additionalDates = [] }
            if choice != .custom { showPicker = false }
        }
    }

    private func label(for date: Date, now: Date) -> String {
        Calendar.current.isDateInToday(date) ? TimeFormat.time(date) : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func row(_ title: String, symbol: String, trailing: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(title)
                    .font(.body.weight(selected ? .semibold : .regular))
                    .foregroundStyle(Color.ink)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(selected ? model.draft.tint.color : Color.ink2)
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(model.draft.tint.color)
                        .transition(.symbolEffect(.drawOn))
                }
            }
            .padding(.vertical, 15)
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 0.5)
        }
    }
}

/// Further moments for the same reminder: "…and again at 12".
struct AlsoAtPanel: View {
    @Binding var draft: ReminderDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Also remind me").eyebrow()
                .padding(.horizontal, 6)
            VStack(spacing: 0) {
                ForEach(Array(draft.additionalDates.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        DatePicker(
                            "Time \(index + 2)",
                            selection: Binding(
                                get: { draft.additionalDates[index] },
                                set: { draft.additionalDates[index] = $0.roundedToMinute }
                            ),
                            in: Date.now...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .tint(Color(white: 0.45))
                        Spacer()
                        Button {
                            withAnimation(Motion.snappy) { _ = draft.additionalDates.remove(at: index) }
                            Haptics.shared.play(.undo)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.ink2)
                                .frame(width: 32, height: 32)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove this time")
                    }
                    .frame(minHeight: 52)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 0.5) }
                }
                Button {
                    let last = draft.allDates.last ?? QuickTimes.suggested()
                    withAnimation(Motion.snappy) { draft.addDate(last.addingTimeInterval(3 * 3600)) }
                    Haptics.shared.play(.step)
                } label: {
                    Text("Add another time")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        }
    }
}

// MARK: - Again

struct AgainStep: View {
    @Bindable var model: WizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            FlowLayout(spacing: 8) {
                ForEach(RepeatRule.allCases) { rule in
                    ChoiceChip(
                        title: rule.label,
                        isSelected: model.draft.repeatRule == rule,
                        tint: model.draft.tint
                    ) {
                        withAnimation(Motion.bouncy) { model.draft.repeatRule = rule }
                    }
                }
            }
            .haptic(.selection, trigger: model.draft.repeatRule)

            if let anchor = model.draft.dueDate {
                RepeatPreview(rule: model.draft.repeatRule, anchor: anchor, tint: model.draft.tint)
            }
        }
    }
}

/// Two weeks of dots that light up wherever the reminder will return.
struct RepeatPreview: View {
    let rule: RepeatRule
    let anchor: Date
    let tint: ReminderTint

    private var days: [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: anchor)
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -offset, to: start) ?? start
        return (0..<21).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Next three weeks").eyebrow()
            let calendar = Calendar.current
            let symbols = calendar.veryShortStandaloneWeekdaySymbols
            let first = calendar.firstWeekday - 1
            let ordered = Array(symbols[first...] + symbols[..<first])
            Grid(horizontalSpacing: 0, verticalSpacing: 12) {
                GridRow {
                    ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.ink3)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<3, id: \.self) { week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            let index = week * 7 + column
                            let day = days[index]
                            let active = rule.occurs(on: day, anchor: anchor)
                            let isAnchor = calendar.isDate(day, inSameDayAs: anchor)
                            ZStack {
                                Circle()
                                    .fill(active ? AnyShapeStyle(tint.color) : AnyShapeStyle(Color.white.opacity(0.1)))
                                    .frame(width: active ? 30 : 8, height: active ? 30 : 8)
                                if active {
                                    Text("\(calendar.component(.day, from: day))")
                                        .font(.mono(.caption2, weight: .semibold))
                                        .foregroundStyle(tint.onColor)
                                }
                            }
                            .overlay {
                                if isAnchor {
                                    Circle().strokeBorder(tint.color, lineWidth: 1.5).frame(width: 38, height: 38)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .animation(Motion.bouncy.delay(Double(index) * 0.012), value: rule)
                        }
                    }
                }
            }
            Text(summary)
                .font(.footnote)
                .foregroundStyle(Color.ink2)
                .contentTransition(.opacity)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
    }

    private var summary: String {
        guard rule != .never, let next = rule.next(after: anchor) else {
            return "Once, \(TimeFormat.dayAndTime(anchor))."
        }
        return "First \(TimeFormat.dayAndTime(anchor)), then \(TimeFormat.dayAndTime(next)) — and on, until you say stop."
    }
}

// MARK: - How

struct HowStep: View {
    @Bindable var model: WizardModel
    @State private var alarmDenied = false

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Delivery.allCases) { delivery in
                DeliveryCard(delivery: delivery, selected: model.draft.delivery == delivery, tint: model.draft.tint) {
                    select(delivery)
                }
            }
            Text(footnote)
                .font(.footnote)
                .foregroundStyle(alarmDenied ? ReminderTint.signal.color : Color.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .contentTransition(.opacity)
        }
        .haptic(.selection, trigger: model.draft.delivery)
    }

    private var footnote: String {
        if alarmDenied { return "Alarms are turned off for Rymynd. You can allow them in Settings → Rymynd." }
        switch model.draft.delivery {
        case .live: return "Appears \(Prefs.leadLabel(Prefs.leadMinutes).lowercased()) and counts down. Change this in Settings."
        case .nudge: return "A time-sensitive notification, right on time."
        case .ring: return "Rings like an alarm. Snooze it, or stop it to mark it done."
        }
    }

    private func select(_ delivery: Delivery) {
        withAnimation(Motion.bouncy) { model.draft.delivery = delivery }
        guard delivery == .ring else {
            alarmDenied = false
            return
        }
        Task { @MainActor in
            switch AlarmScheduler.authorization {
            case .authorized: alarmDenied = false
            case .notDetermined: alarmDenied = !(await AlarmScheduler.requestAuthorization())
            default: alarmDenied = true
            }
        }
    }
}

struct DeliveryCard: View {
    let delivery: Delivery
    let selected: Bool
    let tint: ReminderTint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                DeliveryIllustration(delivery: delivery, tint: tint, active: selected)
                    .frame(width: 78, height: 62)
                VStack(alignment: .leading, spacing: 3) {
                    Text(delivery.title)
                        .font(.headline)
                        .foregroundStyle(Color.ink)
                    Text(delivery.subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().strokeBorder(selected ? tint.color : Color.ink3, lineWidth: 1.5)
                    if selected {
                        Circle().fill(tint.gradient).padding(4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 22, height: 22)
            }
            .padding(14)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(selected ? tint.color.opacity(0.7) : .clear, lineWidth: 1)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22, style: .continuous))
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(PressableStyle())
        .animation(Motion.bouncy, value: selected)
    }
}

/// Tiny living illustrations of each delivery style.
struct DeliveryIllustration: View {
    let delivery: Delivery
    let tint: ReminderTint
    let active: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.color.opacity(0.1))
            switch delivery {
            case .live: island
            case .nudge: banner
            case .ring:
                Image(systemName: "alarm.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(tint.gradient)
                    .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 1.2)), isActive: active)
            }
        }
    }

    /// A Dynamic Island that breathes between compact and expanded.
    private var island: some View {
        PhaseAnimator([false, true], trigger: active) { expanded in
            ZStack {
                Capsule()
                    .fill(Color.black)
                    .frame(width: expanded ? 64 : 44, height: expanded ? 30 : 14)
                HStack(spacing: 4) {
                    Circle().fill(tint.color).frame(width: expanded ? 10 : 6, height: expanded ? 10 : 6)
                    if expanded {
                        Text("4:59")
                            .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .transition(.opacity)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, expanded ? 9 : 4)
                .frame(width: expanded ? 64 : 44)
            }
            .offset(y: -12)
        } animation: { _ in
            .spring(response: 0.55, dampingFraction: 0.72).delay(0.9)
        }
    }

    /// A banner that drops in from the top of a phone.
    private var banner: some View {
        PhaseAnimator([false, true], trigger: active) { shown in
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .frame(width: 58, height: 18)
                .overlay(alignment: .leading) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(tint.gradient).frame(width: 9, height: 9)
                        Capsule().fill(Color.ink.opacity(0.25)).frame(width: 30, height: 3)
                    }
                    .padding(.leading, 5)
                }
                .offset(y: shown ? -12 : -44)
                .opacity(shown ? 1 : 0)
        } animation: { shown in
            shown ? .spring(response: 0.45, dampingFraction: 0.7).delay(0.5) : .easeIn(duration: 0.3).delay(1.6)
        }
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Review / Edit

/// The editor. The title is the hero and is edited in place; everything else lives in one quiet panel.
struct ReviewStep: View {
    @Bindable var model: WizardModel
    let onDelete: () -> Void
    let onComplete: () -> Void

    var body: some View {
        let draft = model.draft
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Title", text: $model.draft.title, axis: .vertical)
                    .font(.display(size: 32, weight: .bold))
                    .tracking(-0.9)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1...4)
                TextField("Add a note", text: $model.draft.notes, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(Color.ink2)
                    .lineLimit(1...4)
            }

            GlassPanel(padding: EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 14)) {
                VStack(spacing: 0) {
                    row("When", value: draft.dueDate.map { TimeFormat.dayAndTime($0) } ?? "Someday", step: .when)
                    ForEach(draft.additionalDates, id: \.self) { date in
                        row("Also", value: TimeFormat.dayAndTime(date), step: .when)
                    }
                    if draft.dueDate != nil {
                        row("Repeat", value: draft.repeatRule.label, step: .again)
                        row("Delivery", value: draft.delivery.title, step: .how)
                    }
                }
            }

            if model.isEditing {
                GlassPanel(padding: EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18)) {
                    VStack(spacing: 0) {
                        actionRow("Mark as done", color: .ink, divider: true, action: onComplete)
                        actionRow("Delete reminder", color: ReminderTint.signal.color, divider: false, action: onDelete)
                    }
                }
            }

            if let prompt = draft.prompt, draft.origin == .intelligence || draft.origin == .typed {
                Text("From “\(prompt)”")
                    .font(.footnote)
                    .foregroundStyle(Color.ink3)
            }
        }
    }

    private func row(_ label: String, value: String, step: WizardModel.Step) -> some View {
        Button {
            model.go(to: step)
        } label: {
            HStack(spacing: 12) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Color.ink2)
                Spacer(minLength: 12)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.ink3)
            }
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 0.5)
        }
    }

    private func actionRow(_ title: String, color: Color, divider: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if divider { Rectangle().fill(Color.hairline).frame(height: 0.5) }
        }
    }
}
