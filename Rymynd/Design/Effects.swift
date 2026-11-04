import SwiftUI

// MARK: - Glyph reveal

/// Reveals text glyph by glyph: each one rises out of a soft blur. Drive `progress` from 0 to 1 with any animation.
struct GlyphRevealRenderer: TextRenderer, Animatable {
    var progress: Double
    /// Portion of the timeline across which glyph start times are staggered.
    var stagger: Double = 0.55
    var rise: Double = 8
    var blur: Double = 6

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let slices = layout.flatMap { line in line.flatMap { run in Array(run) } }
        let count = max(slices.count, 1)
        for (index, slice) in slices.enumerated() {
            let start = Double(index) / Double(count) * stagger
            let local = min(max((progress - start) / max(1 - stagger, 0.001), 0), 1)
            let eased = 1 - pow(1 - local, 3)
            guard eased > 0 else { continue }
            var copy = context
            copy.opacity = eased
            if eased < 1 {
                copy.addFilter(.blur(radius: (1 - eased) * blur))
                copy.translateBy(x: 0, y: (1 - eased) * rise)
            }
            copy.draw(slice, options: .disablesSubpixelQuantization)
        }
    }
}

/// Text that writes itself in whenever its string changes.
struct RevealText: View {
    let text: String
    var duration: Double = 0.9
    @State private var progress: Double = 0

    var body: some View {
        Text(text)
            .textRenderer(GlyphRevealRenderer(progress: progress))
            .onAppear { animateIn() }
            .onChange(of: text) { _, _ in
                progress = 0
                animateIn()
            }
    }

    private func animateIn() {
        withAnimation(.easeOut(duration: duration)) { progress = 1 }
    }
}

// MARK: - Strike

/// Draws a strike line through each line of text, left to right, as `progress` goes 0 → 1.
struct StrikeRenderer: TextRenderer, Animatable {
    var progress: Double
    var color: Color
    var thickness: CGFloat = 1.5

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            context.draw(line)
        }
        guard progress > 0 else { return }
        let lines = Array(layout)
        let perLine = 1 / Double(max(lines.count, 1))
        for (index, line) in lines.enumerated() {
            let local = min(max((progress - Double(index) * perLine) / perLine, 0), 1)
            guard local > 0 else { continue }
            let bounds = line.typographicBounds.rect
            let y = bounds.midY + bounds.height * 0.06
            let rect = CGRect(x: bounds.minX - 1, y: y - thickness / 2, width: (bounds.width + 2) * local, height: thickness)
            context.fill(Path(roundedRect: rect, cornerRadius: thickness / 2), with: .color(color))
        }
    }
}

// MARK: - Particle burst

/// A tiny, restrained burst of dots. Fires whenever `trigger` changes.
struct ParticleBurst: View {
    let trigger: Int
    let tint: Color
    var count = 12
    var radius: CGFloat = 28

    var body: some View {
        KeyframeAnimator(initialValue: 1.0, trigger: trigger) { progress in
            Canvas { context, size in
                guard progress > 0, progress < 1 else { return }
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                context.opacity = 1 - progress * progress
                for index in 0..<count {
                    let angle = Double(index) / Double(count) * 2 * .pi
                    let long = index.isMultiple(of: 2)
                    let inner = radius * (0.55 + 0.6 * progress)
                    let length = (long ? 9 : 5) * (1 - progress) + 1
                    var path = Path()
                    path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                    path.addLine(to: CGPoint(x: center.x + cos(angle) * (inner + length), y: center.y + sin(angle) * (inner + length)))
                    context.stroke(path, with: .color(long ? tint : .white), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
        } keyframes: { _ in
            MoveKeyframe(0.0)
            LinearKeyframe(1.0, duration: 0.7, timingCurve: .easeOut)
        }
        .frame(width: radius * 3, height: radius * 3)
        .allowsHitTesting(false)
    }
}

// MARK: - Intelligence glow

/// A slowly rotating, softly bleeding gradient edge — shown while on-device intelligence is thinking.
struct IntelligenceGlow<S: InsettableShape>: View {
    var shape: S
    var active: Bool
    var lineWidth: CGFloat = 1.5

    static var colors: [Color] {
        [ReminderTint.signal.color, ReminderTint.ice.color, ReminderTint.violet.color,
         ReminderTint.cobalt.color, ReminderTint.volt.color, ReminderTint.signal.color]
    }

    var body: some View {
        TimelineView(.animation(paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // A single travelling highlight on a hairline edge — no rainbow.
            let gradient = AngularGradient(
                stops: [
                    .init(color: .white.opacity(0.08), location: 0),
                    .init(color: .white.opacity(0.9), location: 0.12),
                    .init(color: .white.opacity(0.08), location: 0.3),
                    .init(color: .white.opacity(0.08), location: 1),
                ],
                center: .center,
                angle: .degrees((t * 160).truncatingRemainder(dividingBy: 360))
            )
            shape.strokeBorder(gradient, lineWidth: lineWidth)
        }
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: active)
        .allowsHitTesting(false)
    }
}

// MARK: - Mesh backdrop

/// A living mesh gradient that drifts very slowly. Used sparingly: onboarding and the hero card.
struct MeshBackdrop: View {
    var colors: [Color]
    var speed: Double = 0.22
    var amplitude: Float = 0.18

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = Float(timeline.date.timeIntervalSinceReferenceDate * speed)
            let a = amplitude
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5 + a * 0.5 * sin(t * 0.8), 0], [1, 0],
                    [0, 0.5 + a * sin(t)], [0.5 + a * cos(t * 0.9), 0.5 + a * sin(t * 1.1)], [1, 0.5 + a * cos(t * 1.2)],
                    [0, 1], [0.5 + a * sin(t * 0.7), 1], [1, 1],
                ],
                colors: colors,
                smoothsColors: true
            )
        }
    }

    /// Deep, low-light colours: glass needs something to refract, not something to compete with.
    static func palette(_ tint: ReminderTint, base: Color = .canvas, intensity: Double = 1) -> [Color] {
        let a = tint.deep.opacity(0.55 * intensity), b = tint.companion.deep.opacity(0.5 * intensity)
        let night = Color(red: 0.04, green: 0.05, blue: 0.09)
        return [
            base, night, a,
            night, b, base,
            tint.color.opacity(0.16 * intensity), base, base,
        ]
    }
}

/// The app's backdrop: near-black with slow, deep currents of colour behind the glass.
struct Aurora: View {
    var tint: ReminderTint = .cobalt
    var intensity: Double = 1

    var body: some View {
        Color.canvas.ignoresSafeArea()
    }
}

// MARK: - Shimmer

/// A highlight that sweeps across content, for "thinking" labels.
struct Shimmer: ViewModifier {
    var active: Bool
    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.85), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.5)
                        .offset(x: phase * proxy.size.width)
                        .blendMode(.plusLighter)
                    }
                    .mask(content)
                    .onAppear {
                        phase = -0.6
                        withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.2 }
                    }
                }
            }
    }
}

extension View {
    func shimmer(_ active: Bool = true) -> some View { modifier(Shimmer(active: active)) }
}

// MARK: - Ripple (Metal)

/// A single water-drop ripple, rendered by `Ripple.metal`. Fires whenever `trigger` changes.
struct RippleEffect<T: Equatable>: ViewModifier {
    var origin: CGPoint
    var trigger: T
    var amplitude: Double = 9

    func body(content: Content) -> some View {
        let origin = origin
        let amplitude = amplitude
        let duration = 2.2
        content.keyframeAnimator(initialValue: 0, trigger: trigger) { view, elapsed in
            view.modifier(RippleShaderModifier(origin: origin, elapsed: elapsed, duration: duration, amplitude: amplitude))
        } keyframes: { _ in
            MoveKeyframe(0)
            LinearKeyframe(duration, duration: duration)
        }
    }
}

private struct RippleShaderModifier: ViewModifier, Animatable {
    var origin: CGPoint
    var elapsed: TimeInterval
    var duration: TimeInterval
    var amplitude: Double

    func body(content: Content) -> some View {
        let shader = ShaderLibrary.Ripple(
            .float2(origin),
            .float(elapsed),
            .float(amplitude),
            .float(14),   // frequency
            .float(7),    // decay
            .float(1100)  // speed
        )
        let enabled = elapsed > 0 && elapsed < duration
        let offset = amplitude
        return content.visualEffect { view, _ in
            view.layerEffect(shader, maxSampleOffset: CGSize(width: offset, height: offset), isEnabled: enabled)
        }
    }
}

extension View {
    func ripple<T: Equatable>(at origin: CGPoint, trigger: T, amplitude: Double = 9) -> some View {
        modifier(RippleEffect(origin: origin, trigger: trigger, amplitude: amplitude))
    }
}

// MARK: - Blur transition

struct BlurReplace: Transition {
    var radius: CGFloat = 10
    var scale: CGFloat = 0.96

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .blur(radius: phase.isIdentity ? 0 : radius)
            .scaleEffect(phase.isIdentity ? 1 : scale)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

extension AnyTransition {
    static var softBlur: AnyTransition { AnyTransition(BlurReplace()) }
}

extension Transition where Self == BlurReplace {
    static var softBlur: BlurReplace { BlurReplace() }
}
