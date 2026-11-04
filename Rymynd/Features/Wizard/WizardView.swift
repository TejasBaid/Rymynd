import SwiftUI

@MainActor
@Observable
final class WizardModel {
    enum Step: Int, CaseIterable, Comparable {
        case what, when, again, how, review

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .what: "What should I\nremind you of?"
            case .when: "When should\nit find you?"
            case .again: "Just once, or\nagain and again?"
            case .how: "How should\nit reach you?"
            case .review: "All set?"
            }
        }
    }

    enum WhenChoice: Hashable {
        case in20, inHour, evening, tomorrow, weekend, nextWeek, custom, none
    }

    var step: Step
    var draft: ReminderDraft
    let editing: Reminder?
    /// +1 when moving forward, -1 when moving back. Drives the direction of step transitions.
    var direction: CGFloat = 1
    var whenChoice: WhenChoice?
    var symbolTouched = false
    var tintTouched = false

    init(route: WizardRoute) {
        switch route {
        case .new:
            var draft = ReminderDraft()
            draft.origin = .wizard
            self.draft = draft
            editing = nil
            step = .what
        case .adjust(let draft):
            self.draft = draft
            editing = nil
            step = .review
            symbolTouched = true
            tintTouched = true
            whenChoice = draft.dueDate == nil ? WhenChoice.none : .custom
        case .edit(let reminder):
            draft = ReminderDraft(reminder: reminder)
            editing = reminder
            step = .review
            symbolTouched = true
            tintTouched = true
            whenChoice = reminder.dueDate == nil ? WhenChoice.none : .custom
        }
    }

    var isEditing: Bool { editing != nil }

    /// Without a time there's nothing to repeat or deliver, so those steps fall away.
    var steps: [Step] {
        draft.dueDate == nil ? [.what, .when, .review] : Step.allCases
    }

    var canAdvance: Bool {
        switch step {
        case .what: draft.isValid
        case .when: whenChoice != nil
        default: true
        }
    }

    func next() {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return }
        direction = 1
        withAnimation(Motion.smooth) { step = steps[index + 1] }
        Haptics.shared.play(.step)
    }

    func back() {
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        direction = -1
        withAnimation(Motion.smooth) { step = steps[index - 1] }
        Haptics.shared.play(.step)
    }

    func go(to target: Step) {
        direction = target > step ? 1 : -1
        withAnimation(Motion.smooth) { step = target }
        Haptics.shared.play(.step)
    }

    func titleChanged() {
        if !symbolTouched { draft.symbol = SymbolCatalog.guess(for: draft.title) }
        if !tintTouched { draft.tint = HeuristicParser.tint(for: draft.symbol) }
    }
}

struct WizardView: View {
    @State private var model: WizardModel
    @Environment(\.dismiss) private var dismiss
    @Environment(ReminderStore.self) private var store

    init(route: WizardRoute) {
        _model = State(initialValue: WizardModel(route: route))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if model.step != .review {
                        RevealText(text: model.step.title, duration: 0.8)
                            .font(.display(size: 34, weight: .bold))
                            .tracking(-1.1)
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .id(model.step)
                    }

                    stepContent
                        .id(model.step)
                        .transition(.asymmetric(
                            insertion: .offset(x: 36 * model.direction).combined(with: .softBlur),
                            removal: .offset(x: -36 * model.direction).combined(with: .softBlur)
                        ))
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)

            bottomBar
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background { Aurora(tint: model.draft.tint, intensity: 0.8) }
        .presentationDetents([.large])
        .presentationCornerRadius(36)
        .presentationBackground(Color.canvas)
        .preferredColorScheme(.dark)
        .tint(model.draft.tint.color)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .what: WhatStep(model: model)
        case .when: WhenStep(model: model)
        case .again: AgainStep(model: model)
        case .how: HowStep(model: model)
        case .review: ReviewStep(model: model, onDelete: deleteReminder, onComplete: completeReminder)
        }
    }

    // MARK: Bars

    /// A quiet step counter while creating; nothing at all while editing.
    private var topBar: some View {
        HStack {
            if model.step != .review, let index = model.steps.firstIndex(of: model.step) {
                Text("\(index + 1) / \(model.steps.count - 1)")
                    .font(.mono(.footnote, weight: .medium))
                    .foregroundStyle(Color.ink2)
                    .contentTransition(.numericText())
                    .animation(Motion.snappy, value: model.step)
            }
            Spacer()
            GlassIconButton(systemName: "xmark", size: 36, accessibilityLabel: "Close") { dismiss() }
        }
        .frame(height: 36)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if model.step != model.steps.first, model.step != .review || !model.isEditing {
                GlassIconButton(systemName: "chevron.left", size: 54, accessibilityLabel: "Back") { model.back() }
                    .transition(.softBlur)
            }
            if model.step == .review {
                PrimaryButton(
                    title: model.isEditing ? "Save" : "Remind me",
                    systemImage: model.isEditing ? "checkmark" : "arrow.up",
                    isEnabled: model.draft.isValid,
                    action: save
                )
            } else {
                PrimaryButton(title: "Continue", systemImage: "arrow.right", isEnabled: model.canAdvance) {
                    model.next()
                }
            }
        }
        .animation(Motion.smooth, value: model.step)
    }

    // MARK: Actions

    private func save() {
        let reminders = model.draft.makeReminders(updating: model.editing)
        if model.editing != nil, let first = reminders.first {
            store.update(first)
            if reminders.count > 1 { store.add(contentsOf: Array(reminders.dropFirst())) }
        } else {
            store.add(contentsOf: reminders)
        }
        Haptics.shared.play(.create)
        dismiss()
    }

    private func deleteReminder() {
        guard let editing = model.editing else { return }
        store.delete(id: editing.id)
        Task { await LiveActivityScheduler.end(reminderID: editing.id) }
        Haptics.shared.play(.delete)
        dismiss()
    }

    private func completeReminder() {
        guard let editing = model.editing else { return }
        store.complete(id: editing.id)
        Task { await ReminderActions.didComplete(editing) }
        Haptics.shared.play(.complete)
        dismiss()
    }
}
