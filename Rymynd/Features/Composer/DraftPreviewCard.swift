import SwiftUI

/// What the composer understood. Writes itself in while the model streams, then becomes editable in place.
struct DraftPreviewCard: View {
    @Bindable var model: ComposerModel
    let onAdjust: () -> Void

    private var thinking: Bool { model.phase == .thinking }
    private var draft: ReminderDraft { model.draft }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            titleRow
            if thinking {
                skeleton
                    .transition(.softBlur)
            } else {
                FlowLayout(spacing: 8) {
                    timeMenu
                    ForEach(draft.additionalDates, id: \.self) { date in
                        extraTimeMenu(date)
                            .transition(.softBlur)
                    }
                    if draft.dueDate != nil {
                        addTimeMenu
                        repeatMenu
                    }
                    deliveryMenu
                }
                .animation(Motion.snappy, value: draft.additionalDates)
                .transition(.softBlur.combined(with: .offset(y: 6)))

                actions
                    .transition(.softBlur.combined(with: .offset(y: 10)))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 6) {
            Text(headerText)
                .eyebrow()
                .shimmer(thinking)
                .contentTransition(.opacity)
            Spacer()
        }
    }

    private var headerText: String {
        if thinking { return "Understanding" }
        let count = draft.allDates.count
        if count > 1 { return draft.usedIntelligence ? "Understood · \(count) times" : "\(count) times" }
        return draft.usedIntelligence ? "Understood · on device" : "Here's what I got"
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if thinking {
                    Text(model.streamingTitle.isEmpty ? model.text : model.streamingTitle)
                        .foregroundStyle(model.streamingTitle.isEmpty ? Color.ink3 : Color.ink)
                        .shimmer(model.streamingTitle.isEmpty)
                        .contentTransition(.interpolate)
                        .animation(.easeOut(duration: 0.25), value: model.streamingTitle)
                } else {
                    TextField("What to remember", text: $model.draft.title, axis: .vertical)
                        .lineLimit(1...3)
                        .foregroundStyle(Color.ink)
                }
            }
            .font(.display(size: 26, weight: .semibold))
            .tracking(-0.6)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.titleFrame = $0 }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var skeleton: some View {
        HStack(spacing: 8) {
            ForEach([120.0, 78, 110], id: \.self) { width in
                Capsule()
                    .fill(Color.ink.opacity(0.07))
                    .frame(width: width, height: 34)
            }
        }
        .shimmer()
    }

    // MARK: Menus

    private var timeMenu: some View {
        Menu {
            Section {
                timeOption("In 20 minutes", QuickTimes.inMinutes(20))
                timeOption("In 1 hour", QuickTimes.inMinutes(60))
                timeOption("This evening", QuickTimes.evening())
                timeOption("Tomorrow morning", QuickTimes.tomorrowMorning())
                timeOption("This weekend", QuickTimes.weekend())
            }
            Button("Pick a date & time…", action: onAdjust)
            Button("No time") { set(\.dueDate, nil); model.draft.additionalDates = [] }
        } label: {
            PreviewPill(
                systemImage: "clock",
                text: draft.dueDate.map { TimeFormat.dayAndTime($0) } ?? "Add a time",
                tint: draft.tint,
                emphasized: draft.dueDate == nil
            )
        }
    }

    /// A further moment: tap to remove.
    private func extraTimeMenu(_ date: Date) -> some View {
        Menu {
            Button("Remove this time", role: .destructive) {
                withAnimation(Motion.snappy) { model.draft.additionalDates.removeAll { $0 == date } }
                Haptics.shared.play(.undo)
            }
        } label: {
            PreviewPill(systemImage: "", text: "+ " + TimeFormat.dayAndTime(date), tint: draft.tint)
        }
    }

    /// "Also remind me…" — quick ways to add another moment after the last one.
    private var addTimeMenu: some View {
        let last = draft.allDates.last ?? .now
        let calendar = Calendar.current
        return Menu {
            Section("Also remind me") {
                addOption("An hour later", last.addingTimeInterval(3600))
                addOption("3 hours later", last.addingTimeInterval(3 * 3600))
                if let next = calendar.date(byAdding: .day, value: 1, to: last) {
                    addOption("Same time, next day", next)
                }
                addOption("This evening", QuickTimes.evening())
            }
            Button("Pick a time…", action: onAdjust)
        } label: {
            Text("+ Time")
                .font(.mono(.footnote, weight: .medium))
                .textCase(.uppercase)
                .foregroundStyle(Color.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
        }
    }

    private func addOption(_ title: String, _ date: Date) -> some View {
        Button {
            withAnimation(Motion.snappy) { model.draft.addDate(date) }
            Haptics.shared.play(.step)
        } label: {
            Text(title)
            Text(TimeFormat.dayAndTime(date))
        }
    }

    private func timeOption(_ title: String, _ date: Date) -> some View {
        Button {
            set(\.dueDate, date)
        } label: {
            Text(title)
            Text(TimeFormat.dayAndTime(date))
        }
    }

    private var repeatMenu: some View {
        Menu {
            Picker("Repeat", selection: $model.draft.repeatRule.animation(Motion.snappy)) {
                ForEach(RepeatRule.allCases) { rule in
                    Text(rule.label).tag(rule)
                }
            }
        } label: {
            PreviewPill(systemImage: "repeat", text: draft.repeatRule.shortLabel, tint: draft.tint)
        }
    }

    private var deliveryMenu: some View {
        Menu {
            Picker("Delivery", selection: $model.draft.delivery.animation(Motion.snappy)) {
                ForEach(Delivery.allCases) { delivery in
                    Text(delivery.title).tag(delivery)
                }
            }
        } label: {
            PreviewPill(systemImage: draft.delivery.symbol, text: draft.delivery.title, tint: draft.tint)
        }
    }

    private func set<V>(_ keyPath: WritableKeyPath<ReminderDraft, V>, _ value: V) {
        withAnimation(Motion.snappy) { model.draft[keyPath: keyPath] = value }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 10) {
            SecondaryButton(title: "Adjust", action: onAdjust)

            PrimaryButton(title: "Remind me", systemImage: "arrow.up", isEnabled: draft.isValid) {
                model.confirm()
            }
        }
    }
}

private struct PreviewPill: View {
    var systemImage: String
    var text: String
    var tint: ReminderTint
    var emphasized = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.mono(.footnote, weight: .medium))
                .textCase(.uppercase)
                .foregroundStyle(Color.ink)
                .contentTransition(.numericText())
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.ink3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            Capsule().fill(Color.white.opacity(0.07))
        }
        .overlay {
            Capsule().strokeBorder(emphasized ? ReminderTint.signal.color.opacity(0.8) : Color.white.opacity(0.1), lineWidth: 1)
        }
        .phaseAnimator(emphasized ? [false, true] : [false]) { view, up in
            view.scaleEffect(up ? 1.04 : 1)
        } animation: { _ in .easeInOut(duration: 0.9) }
    }
}

// MARK: - Flow layout

/// Lays children out in rows, wrapping when they run out of room.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * (lineSpacing ?? spacing)
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + (lineSpacing ?? spacing)
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
