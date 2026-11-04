import Foundation

/// User preferences, stored in the App Group so intents running in the background read the same values.
enum Prefs {
    enum Key {
        static let hasOnboarded = "hasOnboarded"
        static let defaultDelivery = "defaultDelivery"
        static let leadMinutes = "leadMinutes"
        static let snoozeMinutes = "snoozeMinutes"
        static let morningHour = "morningHour"
        static let eveningHour = "eveningHour"
        static let haptics = "haptics"
        static let notifyAtTime = "notifyAtTime"
        static let useIntelligence = "useIntelligence"
    }

    static var store: UserDefaults { AppGroup.defaults }

    static func registerDefaults() {
        store.register(defaults: [
            Key.hasOnboarded: false,
            Key.defaultDelivery: Delivery.live.rawValue,
            Key.leadMinutes: 15,
            Key.snoozeMinutes: 10,
            Key.morningHour: 9,
            Key.eveningHour: 19,
            Key.haptics: true,
            Key.notifyAtTime: true,
            Key.useIntelligence: true,
        ])
    }

    static var leadMinutes: Int { store.integer(forKey: Key.leadMinutes) }
    static var snoozeMinutes: Int { max(1, store.integer(forKey: Key.snoozeMinutes)) }
    static var morningHour: Int { store.integer(forKey: Key.morningHour) }
    static var eveningHour: Int { store.integer(forKey: Key.eveningHour) }
    static var notifyAtTime: Bool { store.bool(forKey: Key.notifyAtTime) }
    static var haptics: Bool { store.bool(forKey: Key.haptics) }
    static var useIntelligence: Bool { store.bool(forKey: Key.useIntelligence) }
    static var defaultDelivery: Delivery {
        Delivery(rawValue: store.string(forKey: Key.defaultDelivery) ?? "") ?? .live
    }

    static let leadOptions: [Int] = [0, 5, 15, 30, 60]
    static let snoozeOptions: [Int] = [5, 10, 15, 30, 60]

    static func leadLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: "At the moment"
        case 60: "1 hour before"
        default: "\(minutes) min before"
        }
    }
}
