import SwiftUI

struct HomeView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var composer = ComposerModel()
    @State private var wizard: WizardRoute?
    @State private var showSettings = false
    @State private var toast: Toast?
    @State private var highlighted: UUID?
    @State private var showDone = true
    @State private var scrolled = false
    @State private var heroRipple = 0
    @State private var completingHero: UUID?
    @State private var flight: Flight?
    @State private var landingTarget: TitleTarget?
    @State private var scrollRequest: UUID?
    @State private var viewport: CGRect = .zero
    @State private var openSwipeID: UUID?

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .sheet(item: $wizard) { route in
            WizardView(route: route)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .overlay {
            if let flight {
                FlightLayer(flight: flight, target: landingTarget)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            composer.onCreated = { reminder, source in launch(reminder, from: source) }
        }
        .onChange(of: store.lastCreatedID) { _, id in
            guard let id else { return }
            // Highlight without scrolling: the landing animation needs a still target.
            withAnimation(Motion.snappy) { highlighted = id }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(Motion.smooth) { if highlighted == id { highlighted = nil } }
            }
            if store.nextUp()?.id == id { heroRipple += 1 }
        }
        #if DEBUG
        .task {
            if DemoSupport.has("-openWizard") { wizard = .new }
            if DemoSupport.has("-openEdit"), let first = store.ordered.first(where: { $0.repeatRule != .never }) ?? store.ordered.first { wizard = .edit(first) }
            if DemoSupport.has("-openSettings") { showSettings = true }
            if let text = DemoSupport.value(after: "-compose") {
                try? await Task.sleep(for: .milliseconds(600))
                composer.text = text
                composer.submit()
                if DemoSupport.has("-autoConfirm") {
                    while composer.phase != .preview { try? await Task.sleep(for: .milliseconds(200)) }
                    try? await Task.sleep(for: .seconds(1.2))
                    composer.confirm()
                }
            }
        }
        #endif
        .onChange(of: router.composeRequest, initial: true) { _, request in
            guard let request else { return }
            router.composeRequest = nil
            showSettings = false
            wizard = nil
            if composer.isEngaged { composer.dismiss() }
            Task { @MainActor in
                // Let any sheet finish leaving (and the app finish launching) before taking focus.
                try? await Task.sleep(for: .milliseconds(450))
                switch request.mode {
                case .type: composer.focusRequest += 1
                case .wizard: wizard = .new
                }
            }
        }
        .onChange(of: router.focusedReminderID) { _, id in
            guard let id else { return }
            flash(id)
            router.focusedReminderID = nil
        }
    }

    // MARK: Layout

    private func content(now: Date) -> some View {
        let hero = store.nextUp(now: now)
        let sections = Self.sections(store.ordered, excluding: hero?.id, now: now)
        let done = store.completedToday(now: now)

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DayHeader(now: now, remainingToday: remainingToday(now: now), doneToday: done.count, streak: store.streak(now: now))
                        .padding(.top, 4)

                    NextUpCard(
                        reminder: hero,
                        now: now,
                        doneToday: done.count,
                        hasAnything: !store.reminders.isEmpty,
                        ripple: heroRipple,
                        onComplete: { if let hero { completeHero(hero) } },
                        onOpen: { if let hero { wizard = .edit(hero) } },
                        onSnooze: { if let hero { snooze(hero, minutes: Prefs.snoozeMinutes) } },
                        landingID: flight?.reminderID,
                        onLandingFrame: { landingTarget = TitleTarget(rect: $0, fontSize: 28) }
                    )
                    .padding(.top, 22)

                    ForEach(sections) { section in
                        sectionView(section, now: now)
                    }

                    if !done.isEmpty {
                        doneSection(done)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
                .animation(Motion.smooth, value: store.reminders)
                .overlay {
                    // Dim the list while composing so the preview reads clearly.
                    Color.black
                        .opacity(composer.isEngaged ? 0.55 : 0)
                        .padding(-400)
                        .allowsHitTesting(composer.isEngaged)
                        .onTapGesture { composer.dismiss() }
                        .animation(Motion.smooth, value: composer.isEngaged)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.hard, for: .top)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting, openSwipeID != nil { openSwipeID = nil }
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 70
            } action: { _, isScrolled in
                withAnimation(Motion.snappy) { scrolled = isScrolled }
            }
            .safeAreaBar(edge: .top, spacing: 0) { topBar(now: now) }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    if let toast {
                        ToastView(toast: toast) { self.toast = nil }
                            .transition(.move(edge: .bottom).combined(with: .softBlur))
                    }
                    ComposerDock(
                        model: composer,
                        onAdjust: { draft in wizard = .adjust(draft) },
                        onOpenWizard: { wizard = .new }
                    )
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
                .animation(Motion.bouncy, value: toast?.id)
            }
            .onChange(of: scrollRequest) { _, id in
                guard let id else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: highlighted) { _, id in
                // Scroll to things you came looking for (a notification tap), not to what you just made.
                guard let id, id != store.lastCreatedID else { return }
                withAnimation(Motion.smooth) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { viewport = $0 }
        .background { Aurora(tint: hero.map { $0.isOverdue(at: now) ? .signal : $0.tint } ?? .cobalt, intensity: 0.9) }
        .task(id: toast?.id) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(3.6))
            withAnimation(Motion.smooth) { toast = nil }
        }
    }

    private func topBar(now: Date) -> some View {
        HStack {
            ZStack(alignment: .leading) {
                Wordmark(size: 22)
                    .opacity(scrolled ? 0 : 1)
                    .blur(radius: scrolled ? 6 : 0)
                Text(now.formatted(.dateTime.weekday(.wide)))
                    .font(.display(.headline, weight: .semibold))
                    .opacity(scrolled ? 1 : 0)
                    .offset(y: scrolled ? 0 : 8)
            }
            Spacer()
            GlassIconButton(systemName: "slider.horizontal.3", size: 40, accessibilityLabel: "Settings") {
                showSettings = true
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func sectionHeader(_ title: String, count: Int, color: Color = .ink2) -> some View {
        HStack {
            Text(title).eyebrow(color)
            Spacer()
            Text(String(format: "%02d", count))
                .font(.mono(.caption2, weight: .medium))
                .foregroundStyle(Color.ink3)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func sectionView(_ section: HomeSection, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(section.title, count: section.items.count, color: section.isOverdue ? ReminderTint.signal.color : .ink2)

            GlassPanel {
                VStack(spacing: 0) {
                    ForEach(section.items) { reminder in
                        ReminderRow(
                            reminder: reminder,
                            now: now,
                            style: section.rowStyle,
                            highlighted: highlighted == reminder.id,
                            showsDivider: reminder.id != section.items.last?.id,
                            isLanding: flight?.reminderID == reminder.id,
                            onLandingFrame: {
                                landingTarget = TitleTarget(rect: $0, fontSize: 17)
                            },
                            onComplete: { complete(reminder) },
                            onOpen: { wizard = .edit(reminder) }
                        )
                        .swipeToDelete(id: reminder.id, openID: $openSwipeID) { delete(reminder) }
                        .id(reminder.id)
                        .contextMenu { menu(for: reminder) }
                        .transition(.asymmetric(
                            insertion: .softBlur.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .leading))
                        ))
                    }
                }
            }
        }
        .padding(.top, 28)
    }

    private func doneSection(_ records: [CompletionRecord]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Motion.smooth) { showDone.toggle() }
            } label: {
                HStack(spacing: 8) {
                    sectionHeader("Done today", count: records.count, color: ReminderTint.mint.color)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.ink3)
                        .rotationEffect(.degrees(showDone ? 0 : -90))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if showDone {
                GlassPanel {
                    VStack(spacing: 0) {
                        ForEach(records) { record in
                            DoneRow(record: record) { undo(record) }
                                .transition(.softBlur.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .transition(.softBlur)
            }
        }
        .padding(.top, 28)
    }

    @ViewBuilder
    private func menu(for reminder: Reminder) -> some View {
        Button("Edit", systemImage: "pencil") { wizard = .edit(reminder) }
        Button("Done", systemImage: "checkmark.circle") { complete(reminder, delay: 0) }
        Menu("Snooze", systemImage: "zzz") {
            Button("\(Prefs.snoozeMinutes) minutes") { snooze(reminder, minutes: Prefs.snoozeMinutes) }
            Button("1 hour") { snooze(reminder, minutes: 60) }
            Button("This evening") { snooze(reminder, until: QuickTimes.evening()) }
            Button("Tomorrow morning") { snooze(reminder, until: QuickTimes.tomorrowMorning()) }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { delete(reminder) }
    }

    // MARK: Actions

    private func complete(_ reminder: Reminder, delay: Double = 0.62) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            var record: CompletionRecord?
            withAnimation(Motion.smooth) { record = store.complete(id: reminder.id) }
            await ReminderActions.didComplete(reminder)
            if let record {
                toast = Toast(
                    message: reminder.repeatRule == .never ? "Done" : "Done · next \(nextLabel(for: reminder))",
                    detail: reminder.title,
                    symbol: "checkmark",
                    tint: reminder.tint,
                    undo: {
                        withAnimation(Motion.smooth) { store.undo(record) }
                        Haptics.shared.play(.undo)
                    }
                )
            }
        }
    }

    /// The "Remind me" moment: the title lifts off the preview card, arcs over the list and settles
    /// into its new home — the hero or its row — which reveals it with a sweep of light.
    private func launch(_ reminder: Reminder, from source: CGRect) {
        guard source != .zero else {
            Haptics.shared.play(.create)
            return
        }
        landingTarget = nil
        flight = Flight(reminderID: reminder.id, title: reminder.title, source: source)
        Task { @MainActor in
            // Let the new row lay out and report where it lives.
            try? await Task.sleep(for: .milliseconds(60))
            // If its new home is out of view (or tucked under the composer), bring it in; the flight follows.
            if let target = landingTarget?.rect, target.maxY > viewport.maxY - 170 || target.minY < viewport.minY + 110 {
                scrollRequest = reminder.id
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) { flight?.progress = 1 }
            try? await Task.sleep(for: .milliseconds(620))
            Haptics.shared.play(.create)
            withAnimation(.easeOut(duration: 0.18)) { flight = nil }
        }
    }

    private func completeHero(_ reminder: Reminder) {
        heroRipple += 1
        complete(reminder, delay: 0.75)
    }

    private func undo(_ record: CompletionRecord) {
        withAnimation(Motion.smooth) { store.undo(record) }
        Haptics.shared.play(.undo)
    }

    private func delete(_ reminder: Reminder) {
        withAnimation(Motion.smooth) { _ = store.delete(id: reminder.id) }
        Haptics.shared.play(.delete)
        Task { await LiveActivityScheduler.end(reminderID: reminder.id) }
        toast = Toast(message: "Deleted", detail: reminder.title, symbol: "trash", tint: .steel) {
            withAnimation(Motion.smooth) { store.restore(reminder) }
            Haptics.shared.play(.undo)
        }
    }

    private func snooze(_ reminder: Reminder, minutes: Int) {
        withAnimation(Motion.smooth) { store.snooze(id: reminder.id, minutes: minutes) }
        snoozed(reminder)
    }

    private func snooze(_ reminder: Reminder, until date: Date) {
        withAnimation(Motion.smooth) { store.snooze(id: reminder.id, until: date) }
        snoozed(reminder)
    }

    private func snoozed(_ reminder: Reminder) {
        Haptics.shared.play(.snooze)
        guard let updated = store.reminder(id: reminder.id), let fire = updated.fireDate else { return }
        toast = Toast(message: "Snoozed · \(TimeFormat.dayAndTime(fire))", detail: reminder.title, symbol: "zzz", tint: reminder.tint, undo: nil)
    }

    private func flash(_ id: UUID) {
        withAnimation(Motion.snappy) { highlighted = id }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(Motion.smooth) { if highlighted == id { highlighted = nil } }
        }
    }

    private func nextLabel(for reminder: Reminder) -> String {
        guard let next = store.reminder(id: reminder.id)?.dueDate else { return "soon" }
        return TimeFormat.day(next).lowercased() == "tomorrow" ? "tomorrow" : TimeFormat.day(next)
    }

    private func remainingToday(now: Date) -> Int {
        store.reminders.filter { reminder in
            guard let fire = reminder.fireDate else { return false }
            return Calendar.current.isDateInToday(fire) || fire < now
        }.count
    }

    // MARK: Sections

    static func sections(_ reminders: [Reminder], excluding heroID: UUID?, now: Date) -> [HomeSection] {
        let calendar = Calendar.current
        var overdue: [Reminder] = [], today: [Reminder] = [], tomorrow: [Reminder] = []
        var week: [Reminder] = [], later: [Reminder] = [], someday: [Reminder] = []
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        for reminder in reminders where reminder.id != heroID {
            guard let fire = reminder.fireDate else {
                someday.append(reminder)
                continue
            }
            if fire <= now { overdue.append(reminder) }
            else if calendar.isDateInToday(fire) { today.append(reminder) }
            else if calendar.isDateInTomorrow(fire) { tomorrow.append(reminder) }
            else if fire < weekEnd { week.append(reminder) }
            else { later.append(reminder) }
        }
        return [
            HomeSection(id: "overdue", title: "Waiting on you", items: overdue, rowStyle: .overdue, isOverdue: true),
            HomeSection(id: "today", title: "Later today", items: today, rowStyle: .time),
            HomeSection(id: "tomorrow", title: "Tomorrow", items: tomorrow, rowStyle: .time),
            HomeSection(id: "week", title: "This week", items: week, rowStyle: .dayTime),
            HomeSection(id: "later", title: "Later", items: later, rowStyle: .date),
            HomeSection(id: "someday", title: "Someday", items: someday, rowStyle: .none),
        ].filter { !$0.items.isEmpty }
    }
}

struct HomeSection: Identifiable {
    let id: String
    let title: String
    let items: [Reminder]
    var rowStyle: ReminderRow.TimeStyle
    var isOverdue = false
}

enum WizardRoute: Identifiable {
    case new
    case adjust(ReminderDraft)
    case edit(Reminder)

    var id: String {
        switch self {
        case .new: "new"
        case .adjust: "adjust"
        case .edit(let reminder): reminder.id.uuidString
        }
    }
}

// MARK: - Header

struct DayHeader: View {
    let now: Date
    let remainingToday: Int
    let doneToday: Int
    let streak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(now.formatted(.dateTime.weekday(.wide)))
                .font(.display(size: 46, weight: .bold))
                .tracking(-1.6)
                .foregroundStyle(Color.ink)
            HStack(spacing: 8) {
                Text(now.formatted(.dateTime.day(.twoDigits).month(.abbreviated)))
                dot
                Text(summary)
                    .contentTransition(.numericText())
                if streak > 1 {
                    dot
                    Text("\(streak)D streak")
                        .foregroundStyle(Color.ink)
                }
            }
            .font(.mono(.caption, weight: .medium))
            .textCase(.uppercase)
            .foregroundStyle(Color.ink2)
            .animation(Motion.snappy, value: remainingToday)
            .animation(Motion.snappy, value: doneToday)
        }
        .accessibilityElement(children: .combine)
    }

    private var dot: some View {
        Circle().fill(Color.ink3).frame(width: 3, height: 3)
    }

    private var summary: String {
        switch (remainingToday, doneToday) {
        case (0, 0): "Clear"
        case (0, _): "All done"
        default: "\(remainingToday) left"
        }
    }
}

// MARK: - Toast

struct Toast: Identifiable {
    let id = UUID()
    var message: String
    var detail: String
    var symbol: String
    var tint: ReminderTint
    var undo: (() -> Void)?
}

struct ToastView: View {
    let toast: Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.message).font(.subheadline.weight(.semibold))
                Text(toast.detail).font(.caption).foregroundStyle(Color.ink2).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let undo = toast.undo {
                Button("Undo") {
                    undo()
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(toast.tint.color)
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Flight

struct Flight: Equatable {
    let reminderID: UUID
    let title: String
    let source: CGRect
    var progress: Double = 0
}

struct TitleTarget: Equatable {
    let rect: CGRect
    let fontSize: CGFloat
}

/// Draws the travelling title in screen space.
private struct FlightLayer: View {
    let flight: Flight
    let target: TitleTarget?

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            FlightText(
                progress: flight.progress,
                title: flight.title,
                source: flight.source.offsetBy(dx: -origin.x, dy: -origin.y),
                target: target?.rect.offsetBy(dx: -origin.x, dy: -origin.y),
                targetSize: target?.fontSize ?? 26
            )
        }
    }
}

/// Interpolates position along a gentle arc, shrinking (or growing) to the destination's type size,
/// with a breath of blur at mid-flight. Re-targets live if the list scrolls under it.
private struct FlightText: View, Animatable {
    var progress: Double
    let title: String
    let source: CGRect
    let target: CGRect?
    let targetSize: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private let sourceSize: CGFloat = 26

    var body: some View {
        let end = target ?? source.offsetBy(dx: 0, dy: -240)
        let p = min(max(progress, 0), 1.05)
        let lift = sin(min(p, 1) * .pi) * 46
        let x = source.minX + (end.minX - source.minX) * p
        let y = source.minY + (end.minY - source.minY) * p - lift
        // The row's title is 17pt, the hero's 28pt: infer from the target's line height.
        let scale = 1 + (targetSize / sourceSize - 1) * p

        Text(title)
            .font(.display(size: sourceSize, weight: .semibold))
            .tracking(-0.6)
            .foregroundStyle(Color.ink)
            .lineLimit(2)
            .frame(width: max(source.width, 120), alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(scale, anchor: .topLeading)
            .blur(radius: sin(min(p, 1) * .pi) * 2.5)
            .shadow(color: .black.opacity(0.4 * sin(min(p, 1) * .pi)), radius: 18, y: 12)
            .offset(x: x, y: y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .opacity(target == nil && p > 0.6 ? 1 - (p - 0.6) * 2.5 : 1)
    }
}
