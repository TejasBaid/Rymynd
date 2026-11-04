import SwiftUI

@MainActor
@Observable
final class ComposerModel {
    enum Phase: Equatable {
        case idle
        /// The model is reading the prompt; `streamingTitle` fills in as it writes.
        case thinking
        /// A resolved draft is waiting for confirmation.
        case preview
    }

    var text = ""
    var isFocused = false
    private(set) var phase: Phase = .idle
    var draft = ReminderDraft()
    private(set) var streamingTitle = ""
    /// Bumped on successful creation, for haptics and the send animation.
    private(set) var created = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    /// Where the preview's title sits on screen — the launch point for the landing animation.
    @ObservationIgnored var titleFrame: CGRect = .zero
    /// Called with the first created reminder and the title's launch frame.
    @ObservationIgnored var onCreated: ((Reminder, CGRect) -> Void)?

    /// Whether the composer is taking over attention (dims the list behind it).
    var isEngaged: Bool { phase != .idle }

    var canSubmit: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func submit() {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        task?.cancel()
        streamingTitle = ""
        withAnimation(Motion.smooth) { phase = .thinking }
        Haptics.shared.startThinking()

        task = Task { @MainActor in
            let started = Date.now
            let result = await IntelligenceService.shared.interpret(prompt) { [weak self] title in
                guard let self, self.phase == .thinking else { return }
                self.streamingTitle = title
            }
            // Give the transformation a beat, even when parsing is instant.
            let elapsed = Date.now.timeIntervalSince(started)
            if elapsed < 0.7 { try? await Task.sleep(for: .seconds(0.7 - elapsed)) }
            Haptics.shared.stopThinking()
            guard !Task.isCancelled else { return }
            withAnimation(Motion.smooth) {
                draft = result
                phase = .preview
            }
            Haptics.shared.play(.understood)
        }
    }

    func confirm() {
        guard draft.isValid else { return }
        let reminders = draft.makeReminders()
        let launch = titleFrame
        withAnimation(Motion.smooth) {
            ReminderStore.shared.add(contentsOf: reminders)
            text = ""
            phase = .idle
        }
        created += 1
        if let first = reminders.first, let onCreated {
            onCreated(first, launch)
        } else {
            Haptics.shared.play(.create)
        }
    }

    func dismiss() {
        task?.cancel()
        Haptics.shared.stopThinking()
        withAnimation(Motion.smooth) { phase = .idle }
    }

    /// Hand-off to the wizard: the composer steps aside.
    func handOff() -> ReminderDraft {
        let current = draft
        task?.cancel()
        Haptics.shared.stopThinking()
        withAnimation(Motion.smooth) {
            phase = .idle
            text = ""
        }
        return current
    }

    static let suggestions: [String] = [
        "Call Mom tonight",
        "Water the plants every Sunday at 9",
        "Stretch in 45 minutes",
        "Take vitamins every morning",
        "Pay rent on the 1st",
        "Book the dentist tomorrow at 10",
    ]
}
