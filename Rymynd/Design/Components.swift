import SwiftUI

// MARK: - Wordmark

/// "rymynd" in tight SF Pro Display with a chrome falloff, and a single point of light.
struct Wordmark: View {
    var size: CGFloat = 22
    var reveal: Double = 1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.05) {
            Text("rymynd")
                .font(.display(size: size, weight: .bold))
                .tracking(-size * 0.045)
                .foregroundStyle(Color.ink)
                .textRenderer(GlyphRevealRenderer(progress: reveal, stagger: 0.6, rise: size * 0.3, blur: size * 0.25))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rymynd")
    }
}

// MARK: - Buttons

struct GlassIconButton: View {
    let systemName: String
    var size: CGFloat = 44
    var tint: Color = .ink
    var accessibilityLabel: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Scales gently when pressed. For cards and large tappable surfaces.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The primary call to action: bright white Liquid Glass with dark type. Colour is kept for meaning.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage).contentTransition(.symbolEffect(.replace))
                }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.black : Color.black.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.white.opacity(isEnabled ? 0.94 : 0.4))
        .controlSize(.large)
        .disabled(!isEnabled)
    }
}

/// Secondary action: clear glass with light type.
struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(role == .destructive ? ReminderTint.signal.color : Color.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }
}

// MARK: - Completion circle

/// A hairline ring that floods with the reminder's colour, draws its tick, and throws a few sparks.
struct CompletionCircle: View {
    var isDone: Bool
    var tint: ReminderTint
    var size: CGFloat = 24
    var action: () -> Void

    @State private var burst = 0

    var body: some View {
        Button {
            if !isDone {
                burst += 1
                Haptics.shared.play(.complete)
            } else {
                Haptics.shared.play(.undo)
            }
            action()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(isDone ? 0 : 0.38), lineWidth: 1.5)
                Circle()
                    .fill(tint.color)
                    .scaleEffect(isDone ? 1 : 0.2)
                    .opacity(isDone ? 1 : 0)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(tint.onColor)
                        .transition(.symbolEffect(.drawOn))
                }
            }
            .frame(width: size, height: size)
            .background { ParticleBurst(trigger: burst, tint: tint.color, radius: size * 0.9) }
            .frame(width: 44, height: 44)
            .contentShape(.circle)
        }
        .buttonStyle(PressableStyle(scale: 0.86))
        .animation(Motion.bouncy, value: isDone)
        .accessibilityLabel(isDone ? "Completed" : "Mark as done")
    }
}

// MARK: - Rings, badges & chips

struct ProgressRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// The reminder's glyph in a softly lit, tinted lens.
struct SymbolBadge: View {
    var symbol: String
    var tint: ReminderTint
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(tint.color)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(RadialGradient(colors: [tint.color.opacity(0.32), tint.color.opacity(0.08)], center: .topLeading, startRadius: 0, endRadius: size))
                    .overlay { Circle().strokeBorder(tint.color.opacity(0.35), lineWidth: 0.75) }
            }
            .contentTransition(.symbolEffect(.replace))
    }
}

struct MetaChip: View {
    var systemImage: String
    var text: String
    var tint: Color = .ink2

    var body: some View {
        // Text only: the words carry it.
        Text(text)
            .lineLimit(1)
            .font(.mono(.caption2, weight: .medium))
            .textCase(.uppercase)
            .foregroundStyle(tint)
    }
}

struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

/// A selectable Liquid Glass capsule. Selection lights it with the tint.
struct ChoiceChip: View {
    let title: String
    var systemImage: String?
    var isSelected: Bool
    var tint: ReminderTint = .cobalt
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).imageScale(.small) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? tint.onColor : Color.ink)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint(tint.color).interactive() : .regular.interactive(), in: .capsule)
        .animation(Motion.snappy, value: isSelected)
    }
}

/// A Liquid Glass panel for grouped content.
struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 26
    var padding: EdgeInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }
}
