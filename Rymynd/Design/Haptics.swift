import CoreHaptics
import UIKit

/// Custom Core Haptics patterns, one per moment that matters. Each is designed to feel like its action:
/// a check-off clicks then lands, creation rises, the model "thinks" with a slow heartbeat.
/// Falls back to UIKit feedback generators where Core Haptics isn't available, and respects the Haptics setting.
@MainActor
final class Haptics {
    static let shared = Haptics()

    enum Moment {
        /// Click, then a soft landing.
        case complete
        /// Three rising taps.
        case create
        /// A crisp, bright confirmation when the model has finished.
        case understood
        /// Two falling, softening taps.
        case snooze
        /// A dull thud.
        case delete
        /// A quick double tap.
        case undo
        /// Moving between wizard steps / pages.
        case step
        /// A whisper of a tick, for the final seconds of a countdown.
        case tick
        /// The moment a reminder comes due while you're looking.
        case arrive
    }

    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var thinkingPlayer: CHHapticAdvancedPatternPlayer?

    private init() {
        prepareEngine()
    }

    private func prepareEngine() {
        guard supportsHaptics, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.playsHapticsOnly = true
            engine.resetHandler = { [weak engine] in try? engine?.start() }
            engine.stoppedHandler = { _ in }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    func play(_ moment: Moment) {
        guard Prefs.haptics else { return }
        guard supportsHaptics, let engine else {
            fallback(moment)
            return
        }
        do {
            let pattern = try CHHapticPattern(events: events(for: moment), parameterCurves: curves(for: moment))
            try engine.start()
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback(moment)
        }
    }

    /// A slow, quiet heartbeat that loops while on-device intelligence is working.
    func startThinking() {
        guard Prefs.haptics, supportsHaptics, let engine, thinkingPlayer == nil else { return }
        do {
            let events = [
                tap(at: 0, intensity: 0.32, sharpness: 0.15),
                tap(at: 0.13, intensity: 0.2, sharpness: 0.1),
                // A silent tail sets the loop length.
                hum(at: 0.14, duration: 0.86, intensity: 0.001, sharpness: 0),
            ]
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine.start()
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            try player.start(atTime: CHHapticTimeImmediate)
            thinkingPlayer = player
        } catch {
            thinkingPlayer = nil
        }
    }

    func stopThinking() {
        try? thinkingPlayer?.stop(atTime: CHHapticTimeImmediate)
        thinkingPlayer = nil
    }

    // MARK: Patterns

    private func events(for moment: Moment) -> [CHHapticEvent] {
        switch moment {
        case .complete:
            [tap(at: 0, intensity: 0.55, sharpness: 0.95),
             tap(at: 0.085, intensity: 1.0, sharpness: 0.45),
             hum(at: 0.085, duration: 0.28, intensity: 0.45, sharpness: 0.12)]
        case .create:
            [tap(at: 0, intensity: 0.35, sharpness: 0.55),
             tap(at: 0.07, intensity: 0.6, sharpness: 0.7),
             tap(at: 0.14, intensity: 1.0, sharpness: 0.85)]
        case .understood:
            [tap(at: 0, intensity: 0.85, sharpness: 1.0),
             tap(at: 0.06, intensity: 0.3, sharpness: 1.0)]
        case .snooze:
            [tap(at: 0, intensity: 0.7, sharpness: 0.35),
             tap(at: 0.13, intensity: 0.38, sharpness: 0.15)]
        case .delete:
            [tap(at: 0, intensity: 0.9, sharpness: 0.05),
             hum(at: 0, duration: 0.12, intensity: 0.5, sharpness: 0)]
        case .undo:
            [tap(at: 0, intensity: 0.5, sharpness: 0.5),
             tap(at: 0.08, intensity: 0.5, sharpness: 0.6)]
        case .step:
            [tap(at: 0, intensity: 0.45, sharpness: 0.7)]
        case .tick:
            [tap(at: 0, intensity: 0.3, sharpness: 1.0)]
        case .arrive:
            [tap(at: 0, intensity: 1.0, sharpness: 0.8),
             tap(at: 0.16, intensity: 1.0, sharpness: 0.8),
             hum(at: 0.16, duration: 0.4, intensity: 0.6, sharpness: 0.3)]
        }
    }

    /// Continuous parts decay rather than stopping dead.
    private func curves(for moment: Moment) -> [CHHapticParameterCurve] {
        func decay(from start: TimeInterval, over duration: TimeInterval) -> CHHapticParameterCurve {
            CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [.init(relativeTime: 0, value: 1), .init(relativeTime: duration, value: 0)],
                relativeTime: start
            )
        }
        switch moment {
        case .complete: return [decay(from: 0.085, over: 0.28)]
        case .delete: return [decay(from: 0, over: 0.12)]
        case .arrive: return [decay(from: 0.16, over: 0.4)]
        default: return []
        }
    }

    private func tap(at time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    private func hum(at time: TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time,
            duration: duration
        )
    }

    private func fallback(_ moment: Moment) {
        switch moment {
        case .complete, .create, .arrive: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .understood: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .snooze, .undo: UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .delete: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .step: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .tick: UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}
