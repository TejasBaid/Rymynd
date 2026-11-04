import SwiftUI

/// The floating Liquid Glass composer. Type a sentence and on-device intelligence turns it into a reminder,
/// or tap + for the step-by-step wizard. The preview card morphs out of the same glass.
struct ComposerDock: View {
    @Bindable var model: ComposerModel
    var onAdjust: (ReminderDraft) -> Void
    var onOpenWizard: () -> Void

    @Environment(IntelligenceService.self) private var intelligence
    @FocusState private var focused: Bool
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 10) {
                if model.phase != .idle {
                    DraftPreviewCard(model: model) {
                        onAdjust(model.handOff())
                    }
                    .glassEffect(.regular, in: .rect(cornerRadius: 30, style: .continuous))
                    .glassEffectID("preview", in: glass)
                    .glassEffectTransition(.matchedGeometry)
                } else if focused && model.text.isEmpty {
                    suggestions
                        .transition(.softBlur.combined(with: .offset(y: 12)))
                }

                HStack(alignment: .bottom, spacing: 10) {
                    field
                    actionButton
                }
            }
        }
        .animation(Motion.smooth, value: model.phase)
        .animation(Motion.smooth, value: focused)
        .onChange(of: focused) { _, isFocused in
            model.isFocused = isFocused
            if isFocused { intelligence.prewarm() }
        }
    }

    // MARK: Field

    private var field: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $model.text)
                .font(.body)
                .focused($focused)
                .submitLabel(.go)
                .onSubmit { model.submit() }
                .disabled(model.phase == .thinking)
                .foregroundStyle(model.phase == .idle ? Color.ink : Color.ink2)
        }
        .padding(.horizontal, 22)
        .frame(height: 54)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("field", in: glass)
        .overlay { IntelligenceGlow(shape: Capsule(), active: model.phase == .thinking) }
    }

    private var placeholder: String {
        "Remind me to…"
    }

    private var actionButton: some View {
        let mode: ActionMode = model.phase != .idle ? .close : model.canSubmit ? .send : .wizard
        return Button {
            switch mode {
            case .send:
                focused = false
                model.submit()
            case .wizard:
                focused = false
                onOpenWizard()
            case .close:
                model.dismiss()
            }
        } label: {
            Image(systemName: mode.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(mode == .send ? Color.black : Color.ink)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp)))
                .frame(width: 54, height: 54)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(mode == .send ? .regular.tint(Color.white.opacity(0.92)).interactive() : .regular.interactive(), in: .circle)
        .glassEffectID("action", in: glass)
        .animation(Motion.bouncy, value: mode)
        .accessibilityLabel(mode.label)
    }

    private enum ActionMode {
        case send, wizard, close

        var symbol: String {
            switch self {
            case .send: "arrow.up"
            case .wizard: "plus"
            case .close: "xmark"
            }
        }

        var label: String {
            switch self {
            case .send: "Create reminder"
            case .wizard: "New reminder, step by step"
            case .close: "Cancel"
            }
        }
    }

    // MARK: Suggestions

    private var suggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ComposerModel.suggestions, id: \.self) { suggestion in
                    Button {
                        model.text = suggestion
                        focused = false
                        model.submit()
                    } label: {
                        Text(suggestion)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}
