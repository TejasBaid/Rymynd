import SwiftUI

/// Seven cool, electric inks. Colour carries meaning, so it is used sparingly:
/// a glow behind the hero, a symbol, a filled check. `signal` is reserved for "it's time".
enum ReminderTint: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case cobalt, ice, violet, mint, volt, signal, steel

    var id: String { rawValue }

    var name: String { rawValue.capitalized }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ReminderTint(rawValue: raw) ?? Self.legacy[raw] ?? .cobalt
    }

    /// Names from the first palette, so older data still decodes.
    private static let legacy: [String: ReminderTint] = [
        "ember": .signal, "marigold": .volt, "moss": .mint, "tide": .cobalt,
        "iris": .violet, "rose": .ice, "graphite": .steel,
    ]

    // Monochrome by design. Every reminder is written in white; the one exception is `signal`,
    // which is reserved for "it's time". (The other cases remain so stored data and AlarmKit metadata decode.)
    var color: Color {
        self == .signal ? Color(red: 1.00, green: 0.43, blue: 0.25) : Color(white: 0.95)
    }

    var deep: Color {
        self == .signal ? Color(red: 0.84, green: 0.22, blue: 0.10) : Color(white: 0.7)
    }

    /// Foreground for content sitting on a solid fill of this tint.
    var onColor: Color {
        self == .signal ? .white : Color.black.opacity(0.88)
    }

    var gradient: LinearGradient {
        // Flat by design: colour is a signal, not a texture.
        LinearGradient(colors: [color, color], startPoint: .top, endPoint: .bottom)
    }

    /// A tint that harmonises with this one in backdrops.
    var companion: ReminderTint {
        switch self {
        case .cobalt: .violet
        case .ice: .cobalt
        case .violet: .cobalt
        case .mint: .ice
        case .volt: .mint
        case .signal: .violet
        case .steel: .cobalt
        }
    }
}
