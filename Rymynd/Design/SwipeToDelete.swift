import SwiftUI
import UIKit

/// Swipe a row left to reveal Delete; keep going past the threshold to delete in one motion.
/// Built on a UIKit pan that only begins for clearly horizontal drags, so the list still scrolls freely.
struct SwipeToDelete: ViewModifier {
    let id: UUID
    /// The one row allowed to be open at a time.
    @Binding var openID: UUID?
    var bleed: CGFloat = 16
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var armed = false
    @State private var dragging = false
    @State private var deleting = false
    /// Where the row sat when the current drag began (closed or open).
    @State private var dragBase: CGFloat = 0

    private let reveal: CGFloat = 92
    private var isOpen: Bool { openID == id }
    private var fullSwipe: CGFloat { max(width * 0.6, reveal + 80) }

    func body(content: Content) -> some View {
        content
            .overlay {
                // While open, a tap on the row closes it instead of opening the editor.
                if isOpen && !dragging {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { close() }
                }
            }
            .offset(x: offset)
            .background(alignment: .trailing) { action }
            // Clip the sliding row at the panel's edge, not the row's, and leave room above and below for effects.
            .mask { Rectangle().padding(.horizontal, -bleed).padding(.vertical, -60) }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .gesture(HorizontalPan(canBegin: canBegin, onChange: changed, onEnd: ended))
            .onChange(of: openID) { _, newValue in
                if newValue != id, offset != 0, !dragging, !deleting { settle(to: 0) }
            }
            .accessibilityAction(named: "Delete", onDelete)
    }

    private var action: some View {
        let visible = max(0, -offset - 8)
        return Button(action: commitDelete) {
            ZStack(alignment: armed ? .leading : .center) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ReminderTint.signal.color)
                Text("Delete")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(.horizontal, 16)
                    .opacity(visible > 56 ? 1 : 0)
            }
            .frame(width: visible)
            .padding(.vertical, 6)
            .padding(.trailing, -bleed + 6)
        }
        .buttonStyle(.plain)
        .opacity(visible > 0 ? 1 : 0)
        .animation(Motion.snappy, value: armed)
        .accessibilityHidden(true)
    }

    // MARK: Gesture

    private func canBegin(velocity: CGPoint) -> Bool {
        guard abs(velocity.x) > abs(velocity.y) * 1.3 else { return false }
        // Closed rows only open leftward; an open row can be pushed either way.
        return velocity.x < 0 || offset != 0
    }

    private func changed(_ translation: CGFloat) {
        if !dragging {
            dragging = true
            dragBase = offset
            if openID != id { openID = id }
        }
        var next = dragBase + translation
        // Rubber-band past the resting edge.
        if next > 0 { next = next / 6 }
        offset = min(next, 24)
        let nowArmed = -offset > fullSwipe
        if nowArmed != armed {
            armed = nowArmed
            Haptics.shared.play(nowArmed ? .step : .tick)
        }
    }

    private func ended(_ translation: CGFloat, _ velocity: CGFloat) {
        dragging = false
        let projected = offset + velocity * 0.12
        if armed || (velocity < -1400 && -offset > reveal) {
            commitDelete()
        } else if -projected > reveal * 0.55 {
            settle(to: -reveal)
            openID = id
        } else {
            close()
        }
    }

    private func close() {
        settle(to: 0)
        if openID == id { openID = nil }
    }

    private func settle(to value: CGFloat) {
        armed = false
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { offset = value }
    }

    private func commitDelete() {
        guard !deleting else { return }
        deleting = true
        armed = true
        withAnimation(.easeOut(duration: 0.2)) { offset = -(width + bleed * 2) }
        if openID == id { openID = nil }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            onDelete()
        }
    }
}

extension View {
    func swipeToDelete(id: UUID, openID: Binding<UUID?>, onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(id: id, openID: openID, onDelete: onDelete))
    }
}

/// A pan recogniser that decides at its first movement whether it owns the touch (horizontal) or lets the scroll view have it.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    var canBegin: (CGPoint) -> Bool
    var onChange: (CGFloat) -> Void
    var onEnd: (CGFloat, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.canBegin = canBegin
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(canBegin: canBegin)
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .changed:
            onChange(translation)
        case .ended, .cancelled, .failed:
            onEnd(translation, recognizer.velocity(in: recognizer.view).x)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canBegin: (CGPoint) -> Bool

        init(canBegin: @escaping (CGPoint) -> Bool) {
            self.canBegin = canBegin
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            return canBegin(pan.velocity(in: pan.view))
        }
    }
}
