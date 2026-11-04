import SwiftUI
import UserNotifications

@main
struct RymyndApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Prefs.registerDefaults()
        #if DEBUG
        DemoSupport.applyLaunchArguments()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(ReminderStore.shared)
                .environment(IntelligenceService.shared)
                .environment(AppRouter.shared)
                .preferredColorScheme(.dark)
                .tint(Color.accent)
        }
    }
}

/// Cross-cutting navigation requests: notification taps, shortcuts.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    /// A reminder to scroll to and highlight (e.g. after tapping its notification).
    var focusedReminderID: UUID?
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Prefs.registerDefaults()
        UNUserNotificationCenter.current().delegate = self
        NotificationScheduler.registerCategories()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["reminderID"] as? String,
              let id = UUID(uuidString: raw) else { return }
        await Self.handle(action: response.actionIdentifier, id: id)
    }

    @MainActor
    private static func handle(action: String, id: UUID) async {
        switch action {
        case NotificationScheduler.Action.done:
            await ReminderActions.complete(id: id, origin: .notification)
        case NotificationScheduler.Action.snooze:
            await ReminderActions.snooze(id: id, minutes: Prefs.snoozeMinutes, origin: .notification)
        case NotificationScheduler.Action.snoozeHour:
            await ReminderActions.snooze(id: id, minutes: 60, origin: .notification)
        case UNNotificationDefaultActionIdentifier:
            AppRouter.shared.focusedReminderID = id
        default:
            break
        }
    }
}

struct RootView: View {
    @AppStorage(Prefs.Key.hasOnboarded, store: AppGroup.defaults) private var hasOnboarded = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(IntelligenceService.self) private var intelligence

    var body: some View {
        ZStack {
            if hasOnboarded {
                HomeView()
                    .transition(.asymmetric(insertion: .softBlur.animation(.smooth(duration: 0.9).delay(0.15)), removal: .opacity))
            } else {
                OnboardingView {
                    withAnimation(.smooth(duration: 0.7)) { hasOnboarded = true }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .background(Color.canvas.ignoresSafeArea())
        .onOpenURL { url in
            // rymynd://reminder/<id> — from a Live Activity tap.
            guard url.scheme == "rymynd", url.host() == "reminder",
                  let id = UUID(uuidString: url.lastPathComponent) else { return }
            AppRouter.shared.focusedReminderID = id
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            intelligence.refresh()
            DeliveryCoordinator.shared.setNeedsSync()
        }
    }
}
