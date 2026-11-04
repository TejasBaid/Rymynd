import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(ReminderStore.self) private var store
    @Environment(IntelligenceService.self) private var intelligence

    @AppStorage(Prefs.Key.defaultDelivery, store: AppGroup.defaults) private var defaultDelivery = Delivery.live.rawValue
    @AppStorage(Prefs.Key.leadMinutes, store: AppGroup.defaults) private var leadMinutes = 15
    @AppStorage(Prefs.Key.snoozeMinutes, store: AppGroup.defaults) private var snoozeMinutes = 10
    @AppStorage(Prefs.Key.morningHour, store: AppGroup.defaults) private var morningHour = 9
    @AppStorage(Prefs.Key.eveningHour, store: AppGroup.defaults) private var eveningHour = 19
    @AppStorage(Prefs.Key.haptics, store: AppGroup.defaults) private var haptics = true
    @AppStorage(Prefs.Key.notifyAtTime, store: AppGroup.defaults) private var notifyAtTime = true
    @AppStorage(Prefs.Key.useIntelligence, store: AppGroup.defaults) private var useIntelligence = true
    @AppStorage(Prefs.Key.hasOnboarded, store: AppGroup.defaults) private var hasOnboarded = true

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var liveEnabled = true
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    header
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section {
                    Toggle(isOn: $useIntelligence) {
                        Text("Understand what I type")
                    }
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(intelligence.isAvailable ? ReminderTint.mint.color : ReminderTint.volt.color)
                                .frame(width: 7, height: 7)
                            Text(intelligence.status.label)
                        }
                    }
                } header: {
                    Text("Intelligence")
                } footer: {
                    Text("Runs entirely on your iPhone with Apple Intelligence. When it's unavailable, Rymynd still understands dates and times on its own.")
                }

                Section {
                    Picker(selection: $defaultDelivery) {
                        ForEach(Delivery.allCases) { delivery in
                            Text(delivery.title).tag(delivery.rawValue)
                        }
                    } label: {
                        Text("Reach me with")
                    }
                    Picker(selection: $leadMinutes) {
                        ForEach(Prefs.leadOptions, id: \.self) { minutes in
                            Text(Prefs.leadLabel(minutes)).tag(minutes)
                        }
                    } label: {
                        Text("Live Activity appears")
                    }
                    Toggle(isOn: $notifyAtTime) {
                        Text("Also ping at the exact time")
                    }
                    .disabled(leadMinutes == 0)
                    Picker(selection: $snoozeMinutes) {
                        ForEach(Prefs.snoozeOptions, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    } label: {
                        Text("Snooze for")
                    }
                } header: {
                    Text("Delivery")
                } footer: {
                    Text("Live Activities are scheduled ahead of time and arrive even when Rymynd is closed.")
                }

                Section("Your day") {
                    Picker(selection: $morningHour) {
                        ForEach(5...11, id: \.self) { Text(hourLabel($0)).tag($0) }
                    } label: {
                        Text("Morning means")
                    }
                    Picker(selection: $eveningHour) {
                        ForEach(16...22, id: \.self) { Text(hourLabel($0)).tag($0) }
                    } label: {
                        Text("Evening means")
                    }
                }

                Section("Permissions") {
                    permissionRow("Notifications", symbol: "bell.badge", granted: notificationStatus == .authorized || notificationStatus == .provisional)
                    permissionRow("Live Activities", symbol: "capsule.inset.filled", granted: liveEnabled)
                    permissionRow("Alarms", symbol: "alarm", granted: AlarmScheduler.authorization == .authorized)
                }

                Section("Feel") {
                    Toggle(isOn: $haptics) {
                        Text("Haptics")
                    }
                }

                Section {
                    Button {
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(400))
                            hasOnboarded = false
                        }
                    } label: {
                        Text("Replay introduction")
                    }
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Text("Clear done history")
                    }
                    .confirmationDialog("Clear your done history?", isPresented: $confirmClear, titleVisibility: .visible) {
                        Button("Clear History", role: .destructive) { store.clearHistory() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { Aurora(tint: .cobalt, intensity: 0.7) }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .task { await refreshPermissions() }
        .onChange(of: leadMinutes) { _, _ in DeliveryCoordinator.shared.setNeedsSync() }
        .onChange(of: notifyAtTime) { _, _ in DeliveryCoordinator.shared.setNeedsSync() }
        .onChange(of: snoozeMinutes) { _, _ in
            NotificationScheduler.registerCategories()
            DeliveryCoordinator.shared.setNeedsSync()
        }
        .onChange(of: useIntelligence) { _, _ in intelligence.refresh() }
        .haptic(.selection, trigger: leadMinutes)
        .haptic(.selection, trigger: defaultDelivery)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Wordmark(size: 34)
            HStack(spacing: 24) {
                stat("\(store.completions.count)", "done")
                stat("\(store.streak())", store.streak() == 1 ? "day streak" : "day streak")
                stat("\(store.reminders.count)", "waiting")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.ink2)
        }
    }

    private func permissionRow(_ title: String, symbol: String, granted: Bool) -> some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(Color.ink)
                Spacer()
                Text(granted ? "On" : "Off")
                    .foregroundStyle(granted ? ReminderTint.mint.color : Color.ink2)
                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ink3)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func refreshPermissions() async {
        notificationStatus = await NotificationScheduler.authorizationStatus()
        liveEnabled = LiveActivityScheduler.isEnabled
    }
}
