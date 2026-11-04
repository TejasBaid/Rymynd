import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0
    @State private var direction: CGFloat = 1
    private let pageCount = 4

    private var palette: ReminderTint {
        [ReminderTint.cobalt, .violet, .ice, .mint][page]
    }

    var body: some View {
        ZStack {
            Aurora(tint: palette, intensity: 1.2)

            VStack(spacing: 0) {
                ZStack {
                    pageView(page)
                        .id(page)
                        .transition(.asymmetric(
                            insertion: .offset(x: 60 * direction).combined(with: .softBlur),
                            removal: .offset(x: -60 * direction).combined(with: .softBlur)
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width < -60 { go(page + 1) }
                    if value.translation.width > 60 { go(page - 1) }
                }
        )
        .onChange(of: page) { _, _ in Haptics.shared.play(.step) }
        #if DEBUG
        .onAppear {
            if let value = DemoSupport.value(after: "-onboardingPage"), let index = Int(value) { page = index }
        }
        #endif
    }

    @ViewBuilder
    private func pageView(_ index: Int) -> some View {
        switch index {
        case 0: WelcomePage()
        case 1: FeaturePage(
            eyebrow: "Just say it",
            title: "Type it the way\nyou'd say it.",
            message: "Apple Intelligence, running privately on your iPhone, turns a quick sentence into a reminder — what, when, how often.",
            contentHeight: 270,
            content: { TypingDemo() }
        )
        case 2: FeaturePage(
            eyebrow: "It finds you",
            title: "Arrives live,\nright on time.",
            message: "Reminders appear as Live Activities on your Lock Screen and in the Dynamic Island, counting down — then tap you on the shoulder.",
            contentHeight: 830,
            content: { LockScreenDemo() }
        )
        default: PermissionsPage()
        }
    }

    private var footer: some View {
        VStack(spacing: 22) {
            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.ink.opacity(0.14)))
                        .frame(width: index == page ? 24 : 7, height: 7)
                        .onTapGesture { go(index) }
                }
            }
            .animation(Motion.bouncy, value: page)

            PrimaryButton(
                title: page == 0 ? "Begin" : page == pageCount - 1 ? "Get started" : "Continue",
                systemImage: "arrow.right"
            ) {
                if page == pageCount - 1 { onFinish() } else { go(page + 1) }
            }
            .animation(Motion.smooth, value: page)
        }
    }

    private func go(_ target: Int) {
        guard target >= 0, target < pageCount, target != page else { return }
        direction = target > page ? 1 : -1
        withAnimation(.smooth(duration: 0.55)) { page = target }
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    @State private var reveal: Double = 0
    @State private var showTagline = false

    var body: some View {
        VStack(spacing: 34) {
            Spacer()
            ZStack {
                GlassDial()
                    .frame(width: 270, height: 270)
                Wordmark(size: 54, reveal: reveal)
            }
            if showTagline {
                VStack(spacing: 14) {
                    RevealText(text: "Say it once.\nIt finds you.", duration: 1.1)
                        .font(.display(size: 34, weight: .bold))
                        .tracking(-1.2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.ink)
                    Text("Reminders that arrive live — on your Lock Screen and in the Dynamic Island.")
                        .font(.subheadline)
                        .foregroundStyle(Color.ink2)
                        .multilineTextAlignment(.center)
                }
                .transition(.softBlur)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).delay(0.3)) { reveal = 1 }
            withAnimation(.smooth(duration: 0.8).delay(1.2)) { showTagline = true }
        }
    }
}

/// A disc of Liquid Glass with a bezel of ticks; a bright arc sweeps the hour like a second hand.
private struct GlassDial: View {
    @State private var appeared = false

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let sweep = (t / 8).truncatingRemainder(dividingBy: 1)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 14
                let count = 72
                for index in 0..<count {
                    let fraction = Double(index) / Double(count)
                    let angle = fraction * 2 * .pi - .pi / 2
                    let major = index.isMultiple(of: 6)
                    let length: CGFloat = major ? 11 : 6
                    // Ticks just behind the sweep glow, then fade.
                    let behind = (sweep - fraction + 1).truncatingRemainder(dividingBy: 1)
                    let glow = max(0, 1 - behind * 3.2)
                    var path = Path()
                    path.move(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                    path.addLine(to: CGPoint(x: center.x + cos(angle) * (radius - length), y: center.y + sin(angle) * (radius - length)))
                    let base = major ? 0.32 : 0.16
                    context.stroke(
                        path,
                        with: .color(glow > 0.02 ? Color.white.opacity(base + glow * 0.75) : .white.opacity(base)),
                        style: StrokeStyle(lineWidth: major ? 1.6 : 1.1, lineCap: .round)
                    )
                }
            }
        }
        .padding(6)
        .glassEffect(.clear, in: .circle)
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { appeared = true } }
    }
}

private struct FeaturePage<Content: View>: View {
    let eyebrow: String
    let title: String
    let message: String
    var contentHeight: CGFloat = 460
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The demo takes whatever height is left and scales down to fit smaller phones.
            GeometryReader { proxy in
                content()
                    .scaleEffect(min(1, proxy.size.height / contentHeight))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
            VStack(alignment: .leading, spacing: 12) {
                Text(eyebrow).eyebrow()
                RevealText(text: title, duration: 0.9)
                    .font(.display(size: 34, weight: .bold))
                    .tracking(-1.2)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.body)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .layoutPriority(1)
        }
    }
}

// MARK: - Typing demo

private struct TypingDemo: View {
    @State private var typed = ""
    @State private var stage = 0 // 0 typing · 1 thinking · 2 understood
    private let sentence = "pick up dry cleaning tomorrow at 5"

    var body: some View {
        VStack(spacing: 14) {
            if stage == 2 {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Understood · on device").eyebrow()
                    RevealText(text: "Pick up dry cleaning", duration: 0.7)
                        .font(.display(size: 22, weight: .medium))
                        .foregroundStyle(Color.ink)
                    HStack(spacing: 8) {
                        pill("Tomorrow, 5:00 PM")
                        pill("Live Activity")
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
                .transition(.softBlur.combined(with: .offset(y: 24)))
            }

            HStack(spacing: 10) {
                Text("\(Text(typed.isEmpty ? "Remind me to…" : typed).foregroundStyle(typed.isEmpty ? Color.ink3 : Color.ink))\(Text(stage == 0 ? "|" : "").foregroundStyle(Color.accent))")
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
            .glassEffect(.regular, in: .capsule)
            .overlay { IntelligenceGlow(shape: Capsule(), active: stage == 1) }
        }
        .padding(.horizontal, 26)
        .frame(height: 260, alignment: .bottom)
        .task { await loop() }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.mono(.caption, weight: .medium))
            .textCase(.uppercase)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
    }

    private func loop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(700))
            for character in sentence {
                guard !Task.isCancelled else { return }
                typed.append(character)
                try? await Task.sleep(for: .milliseconds(Int.random(in: 30...80)))
            }
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(Motion.smooth) { stage = 1 }
            try? await Task.sleep(for: .milliseconds(1300))
            withAnimation(Motion.smooth) { stage = 2 }
            try? await Task.sleep(for: .seconds(3.4))
            withAnimation(Motion.smooth) {
                stage = 0
                typed = ""
            }
        }
    }
}

// MARK: - Lock Screen demo

/// A true-scale Lock Screen (scaled down by the page) that plays the full life of a reminder using the
/// app's real Live Activity views: it arrives, counts down in the Dynamic Island, comes due, and is done.
private struct LockScreenDemo: View {
    enum Stage { case empty, arrived, expanded, due, done }

    @State private var stage: Stage = .empty
    @State private var target = Date.now.addingTimeInterval(5 * 60)
    private let reminderID = UUID().uuidString

    private var state: ReminderActivityAttributes.ContentState {
        .init(
            title: "Call Mom", note: "About the flights", symbol: "phone", tint: .cobalt,
            fireDate: stage == .due || stage == .done ? .now.addingTimeInterval(-1) : target,
            windowStart: target.addingTimeInterval(-15 * 60),
            stage: stage == .done ? .done : .upcoming, repeatLabel: nil
        )
    }

    private var phase: ActivityPhase {
        switch stage {
        case .due: .due
        case .done: .done
        default: .counting
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(white: 0.06)

            VStack(spacing: 0) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 20, weight: .semibold))
                Text("9:41")
                    .font(.system(size: 112, weight: .bold, design: .rounded))
                    .tracking(-2)
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.top, 92)

            island
                .padding(.top, 14)

            VStack {
                Spacer()
                if stage != .empty {
                    ReminderActivityCard(state: state, reminderID: reminderID, phase: phase)
                        .background(Color.activityInk.opacity(0.78), in: .rect(cornerRadius: 26, style: .continuous))
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .bottom).combined(with: .softBlur))
                        .animation(Motion.smooth, value: phase)
                }
                HStack {
                    lockButton("flashlight.off.fill")
                    Spacer()
                    lockButton("camera.fill")
                }
                .padding(.horizontal, 46)
                .padding(.top, 26)
                .padding(.bottom, 34)
            }
        }
        .frame(width: 402, height: 800)
        .clipShape(.rect(cornerRadius: 64, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 64, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 10)
        }
        .shadow(color: .black.opacity(0.25), radius: 40, y: 30)
        .allowsHitTesting(false)
        .environment(\.colorScheme, .dark)
        .task { await loop() }
    }

    private func lockButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 58, height: 58)
            .background(.white.opacity(0.14), in: .circle)
    }

    private var island: some View {
        let expanded = stage == .expanded
        let compact = stage == .arrived || stage == .due || stage == .done
        return ZStack {
            RoundedRectangle(cornerRadius: expanded ? 46 : 22, style: .continuous).fill(Color.black)
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ActivityRing(start: state.windowStart, end: state.fireDate, symbol: "phone", tint: ReminderTint.cobalt.color, size: 44)
                        Spacer()
                        Text(timerInterval: .countdown(to: target), countsDown: true)
                            .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(ReminderTint.cobalt.color)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 84, alignment: .trailing)
                    }
                    Text("Call Mom")
                        .font(.system(.title3, design: .default, weight: .semibold))
                        .foregroundStyle(.white)
                    ActivityActions(state: state, reminderID: reminderID, phase: .counting, compact: true)
                }
                .padding(18)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if compact {
                HStack {
                    Image(systemName: stage == .done ? "checkmark" : "phone.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ReminderTint.cobalt.color)
                    Spacer()
                    Group {
                        switch stage {
                        case .due: Text("Now")
                        case .done: Text("Done")
                        default: Text(timerInterval: .countdown(to: target), countsDown: true).monospacedDigit()
                        }
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(ReminderTint.cobalt.color)
                    .frame(width: 46, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .transition(.opacity)
            }
        }
        .frame(width: expanded ? 374 : compact ? 236 : 126, height: expanded ? 178 : 37)
        .animation(.spring(response: 0.5, dampingFraction: 0.74), value: stage)
    }

    private func loop() async {
        while !Task.isCancelled {
            target = Date.now.addingTimeInterval(5 * 60)
            withAnimation(Motion.smooth) { stage = .empty }
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { stage = .arrived }
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.74)) { stage = .expanded }
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { stage = .arrived }
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(Motion.smooth) { stage = .due }
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(Motion.smooth) { stage = .done }
            try? await Task.sleep(for: .seconds(2.2))
        }
    }
}

// MARK: - Permissions

private struct PermissionsPage: View {
    @State private var notifications: Grant = .unknown
    @State private var alarms: Grant = .unknown
    @State private var liveActivities = true

    enum Grant { case unknown, granted, denied }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text("One last thing").eyebrow()
                RevealText(text: "Let it\nreach you.", duration: 0.9)
                    .font(.display(size: 40, weight: .bold))
                    .tracking(-1.4)
                    .foregroundStyle(Color.ink)
                Text("Rymynd only speaks up at the moment you set. Everything stays on your iPhone.")
                    .font(.body)
                    .foregroundStyle(Color.ink2)
            }
            .padding(.bottom, 34)

            VStack(spacing: 12) {
                PermissionRow(
                    symbol: "bell.badge",
                    tint: .ice,
                    title: "Notifications",
                    detail: "So reminders can arrive on time.",
                    grant: notifications
                ) {
                    let granted = await NotificationScheduler.requestAuthorization()
                    notifications = granted ? .granted : .denied
                    DeliveryCoordinator.shared.setNeedsSync()
                }
                PermissionRow(
                    symbol: "alarm",
                    tint: .violet,
                    title: "Alarms",
                    detail: "Optional. For can't-miss reminders that ring through Silent.",
                    grant: alarms
                ) {
                    alarms = await AlarmScheduler.requestAuthorization() ? .granted : .denied
                }
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Activities").font(.headline)
                        Text(liveActivities ? "On — reminders will appear on your Lock Screen." : "Off — turn them on in Settings → Rymynd.")
                            .font(.footnote)
                            .foregroundStyle(Color.ink2)
                    }
                    Spacer()
                    Image(systemName: liveActivities ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.title3)
                        .foregroundStyle(liveActivities ? ReminderTint.mint.color : ReminderTint.volt.color)
                }
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .task {
            let status = await NotificationScheduler.authorizationStatus()
            notifications = status == .authorized || status == .provisional ? .granted : status == .denied ? .denied : .unknown
            switch AlarmScheduler.authorization {
            case .authorized: alarms = .granted
            case .denied: alarms = .denied
            default: alarms = .unknown
            }
            liveActivities = LiveActivityScheduler.isEnabled
        }
    }
}

private struct PermissionRow: View {
    let symbol: String
    let tint: ReminderTint
    let title: String
    let detail: String
    let grant: PermissionsPage.Grant
    let request: () async -> Void

    @State private var working = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.footnote).foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ZStack {
                switch grant {
                case .granted:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(ReminderTint.mint.color)
                        .transition(.symbolEffect(.drawOn))
                case .denied:
                    Text("Off")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ink3)
                        .transition(.softBlur)
                case .unknown:
                    Button {
                        guard !working else { return }
                        working = true
                        Task {
                            await request()
                            working = false
                        }
                    } label: {
                        Text("Allow")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.white)
                    .transition(.softBlur)
                }
            }
            .animation(Motion.bouncy, value: grant)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
        .haptic(.success, trigger: grant == .granted)
    }
}
