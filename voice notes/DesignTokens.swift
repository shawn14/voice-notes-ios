//
//  DesignTokens.swift
//  voice notes
//
//  One type scale, one spacing scale, one set of radii, one touch-target
//  floor. Added 2026-08-20 during the UX redesign: the app had 97 hardcoded
//  font sizes, zero Dynamic Type support, and no typography tokens at all.
//
//  RULES THIS FILE EXISTS TO ENFORCE
//  1. Never `.font(.system(size:))` in a view. Use `EEONType`. Every style
//     here is built on a semantic text style, so text scales with the user's
//     Text Size setting instead of ignoring it.
//  2. Never a tap target under `EEONLayout.minTarget` (44pt — Apple's floor).
//  3. Never `.lineLimit(1)` on a label that can hold a real word. Let it wrap
//     or let the container grow; truncation is a bug, not a layout.
//

import SwiftUI
import UIKit

// MARK: - Type scale

/// The complete set of text styles the app is allowed to use. Each maps to a
/// system text style so Dynamic Type works for free; weight is the only thing
/// we customize.
enum EEONType {
    /// Screen titles — "Your notes", "Tasks".
    static let screenTitle = Font.title2.weight(.bold)
    /// Section headers inside a screen.
    static let section = Font.subheadline.weight(.semibold)
    /// A note or task title in a list — the thing you read first.
    static let itemTitle = Font.headline
    /// Body copy: note text, long-form content.
    static let body = Font.body
    /// Supporting line under a title: preview text.
    static let preview = Font.subheadline
    /// Metadata: timestamps, durations, counts, categories.
    static let meta = Font.caption
    /// Control labels: buttons, chips, pills.
    static let control = Font.subheadline.weight(.semibold)
    /// The smallest legible step. Use sparingly — badges only.
    static let badge = Font.caption2.weight(.semibold)
}

// MARK: - Layout

enum EEONLayout {
    /// Apple's minimum tap target. Nothing interactive may be smaller.
    static let minTarget: CGFloat = 44

    // Spacing ramp — four steps, no ad-hoc values.
    static let tight: CGFloat = 6
    static let snug: CGFloat = 10
    static let standard: CGFloat = 16
    static let loose: CGFloat = 24

    /// Horizontal screen margin. One value, every screen.
    static let screenMargin: CGFloat = 16

    // Corner radii — two steps only.
    /// Cards, sheets, containers.
    static let cardRadius: CGFloat = 14
    /// Chips, pills, small controls.
    static let chipRadius: CGFloat = 10
}

// MARK: - Modifiers

extension View {
    /// Guarantees a tappable view meets the 44pt minimum without changing its
    /// visual size — the hit area grows, the artwork doesn't.
    func eeonTapTarget() -> some View {
        frame(minWidth: EEONLayout.minTarget, minHeight: EEONLayout.minTarget)
            .contentShape(Rectangle())
    }

    /// Standard horizontal screen margin.
    func eeonScreenPadding() -> some View {
        padding(.horizontal, EEONLayout.screenMargin)
    }
}

// MARK: - Settings row

/// The one settings row. Before this existed, every row hand-rolled its own
/// HStack — which is how two icon treatments (circle badge vs bare glyph) and
/// eight arbitrary icon colors ended up alternating inside a single section.
///
/// One icon treatment, one column width, one type pairing, 44pt minimum.
/// Colour is limited to two roles: `.normal` (brand) and `.destructive`.
struct EEONSettingsRow<Trailing: View>: View {
    enum Role {
        case normal, destructive

        var tint: Color {
            switch self {
            case .normal: return Color("EEONAccentAI")
            case .destructive: return .red
            }
        }
    }

    let icon: String
    var role: Role = .normal
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: EEONLayout.standard) {
            ZStack {
                Circle()
                    .fill(role.tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(role.tint)
            }
            .frame(width: EEONLayout.minTarget, height: EEONLayout.minTarget)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(EEONType.body)
                    .foregroundStyle(role == .destructive ? Color.red : Color.eeonTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: EEONLayout.tight)

            trailing()
        }
        .frame(minHeight: EEONLayout.minTarget)
        .padding(.vertical, 2)
    }
}

extension EEONSettingsRow where Trailing == EmptyView {
    init(icon: String, role: Role = .normal, title: String, subtitle: String? = nil) {
        self.init(icon: icon, role: role, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// The standard disclosure chevron, so no row invents its own.
struct EEONChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(EEONType.meta)
            .foregroundStyle(.eeonTextTertiary)
    }
}

/// The one settings icon treatment. Every settings row used to pick its own —
/// some wrapped in a tinted circle, most bare — and its own colour from a pool
/// of eight. This gives them all the same badge, aligned to the same column.
struct EEONSettingsIcon: View {
    let systemName: String
    var destructive: Bool = false

    private var tint: Color {
        destructive ? .red : Color("EEONAccentAI")
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.15))
                .frame(width: 36, height: 36)
            Image(systemName: systemName)
                .font(.callout)
                .foregroundStyle(tint)
        }
        .frame(width: EEONLayout.minTarget, height: EEONLayout.minTarget)
    }
}

// MARK: - Swipe actions

/// One button revealed by a row swipe: icon over a caption on a solid tint,
/// the way Stock Alarm's alert rows do it. No confirmation dialogs — the
/// swipe plus the tap is the consent.
struct EEONSwipeAction: Identifiable {
    var label: String
    var systemImage: String
    var tint: Color
    var isDestructive: Bool = false
    var handler: () -> Void

    var id: String { label }

    static func edit(_ handler: @escaping () -> Void) -> EEONSwipeAction {
        EEONSwipeAction(label: "Edit", systemImage: "pencil", tint: Color(.systemGray), handler: handler)
    }

    static func share(_ handler: @escaping () -> Void) -> EEONSwipeAction {
        EEONSwipeAction(label: "Share", systemImage: "square.and.arrow.up", tint: .eeonAccentAI, handler: handler)
    }

    static func delete(_ handler: @escaping () -> Void) -> EEONSwipeAction {
        EEONSwipeAction(label: "Delete", systemImage: "trash", tint: .red, isDestructive: true, handler: handler)
    }
}

/// Drives a `.sheet(item:)` share sheet from a swipe "Share" action.
struct EEONSharePayload: Identifiable {
    let id = UUID()
    let text: String
}

/// Swipe actions for rows that live in a ScrollView/LazyVStack rather than
/// a `List` (Home, Tasks). Native `.swipeActions` only works inside `List`.
///
/// The drag is a UIKit pan recognizer, not a SwiftUI `DragGesture`. A SwiftUI
/// drag inside a ScrollView loses to the scroll view unpredictably on device
/// (2026-09-01: Shawn found the swipe only "sometimes" worked on Home). The
/// pan begins only when the first movement is horizontal, so vertical
/// scrolling is never hijacked, and once it has begun the scroll view yields.
struct EEONSwipeActionsRow<Content: View>: View {
    var actions: [EEONSwipeAction]
    var cornerRadius: CGFloat = EEONLayout.cardRadius
    var background: Color = .eeonCard
    /// When false a long drag only reveals the buttons; a tap is required.
    /// Notes use this so a flick can never destroy a note and its audio.
    var allowsFullSwipe: Bool = true
    let content: Content

    @State private var offset: CGFloat = 0
    @State private var isOpen = false

    private let buttonWidth: CGFloat = 68
    /// Drag distance (plus a little velocity) past which a swipe commits the
    /// last action without a tap, roughly half a phone-width row.
    private let fullSwipeDistance: CGFloat = 200

    private var actionsWidth: CGFloat { buttonWidth * CGFloat(max(actions.count, 1)) }

    init(
        actions: [EEONSwipeAction],
        cornerRadius: CGFloat = EEONLayout.cardRadius,
        background: Color = .eeonCard,
        allowsFullSwipe: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.actions = actions
        self.cornerRadius = cornerRadius
        self.background = background
        self.allowsFullSwipe = allowsFullSwipe
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < -1 || isOpen {
                HStack(spacing: 0) {
                    ForEach(actions) { action in
                        Button {
                            perform(action)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: action.systemImage)
                                    .font(.title3.weight(.semibold))
                                Text(action.label)
                                    .font(EEONType.badge)
                            }
                            .foregroundStyle(.white)
                            .frame(width: buttonWidth)
                            .frame(maxHeight: .infinity)
                            .background(action.tint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(action.label)
                    }
                }
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(background)
                .overlay {
                    if isOpen {
                        // Native feel: tapping the row while the buttons are
                        // showing closes them instead of opening the row.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { settle(open: false) }
                    }
                }
                .offset(x: offset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .gesture(EEONHorizontalPan(
            onChanged: { dx in
                let base = isOpen ? -actionsWidth : 0
                offset = max(-actionsWidth, min(0, base + dx))
            },
            onEnded: { dx, vx in
                let base = isOpen ? -actionsWidth : 0
                let projected = base + dx + vx * 0.12
                if allowsFullSwipe, let last = actions.last, projected < -fullSwipeDistance {
                    perform(last)
                } else {
                    settle(open: offset < -actionsWidth * 0.4)
                }
            }
        ))
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: offset)
    }

    private func settle(open: Bool) {
        isOpen = open
        offset = open ? -actionsWidth : 0
    }

    private func perform(_ action: EEONSwipeAction) {
        if action.isDestructive {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        isOpen = false
        offset = 0
        action.handler()
    }
}

/// A UIKit pan that only begins on horizontal movement. Inside a vertical
/// ScrollView this is what makes a row swipe coexist with scrolling the way
/// `List` swipe actions do: vertical pans fail here and go to the scroll
/// view; horizontal pans begin here and the scroll view stays put.
struct EEONHorizontalPan: UIGestureRecognizerRepresentable {
    var onChanged: (CGFloat) -> Void
    /// Horizontal translation and horizontal velocity (points/second).
    var onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let coordinator = context.coordinator
        let translation = recognizer.translation(in: recognizer.view)
        switch recognizer.state {
        case .began:
            coordinator.axis = .undecided
        case .changed:
            // Lock the axis on the first meaningful movement. A horizontal
            // lock drives the swipe (and UIKit cancels the row's button/link
            // touch); a vertical lock is left entirely to the scroll view,
            // which recognizes simultaneously, so scrolling never stutters.
            if coordinator.axis == .undecided,
               max(abs(translation.x), abs(translation.y)) > 6 {
                coordinator.axis = abs(translation.x) > abs(translation.y) ? .horizontal : .vertical
            }
            if coordinator.axis == .horizontal {
                onChanged(translation.x)
            }
        case .ended:
            if coordinator.axis == .horizontal {
                onEnded(translation.x, recognizer.velocity(in: recognizer.view).x)
            }
            coordinator.axis = .undecided
        case .cancelled, .failed:
            if coordinator.axis == .horizontal {
                onEnded(translation.x, 0)
            }
            coordinator.axis = .undecided
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        enum Axis { case undecided, horizontal, vertical }
        var axis: Axis = .undecided

        // Always begin so the axis lock (not a velocity guess at touch-down)
        // decides direction — a slow horizontal drag that starts over the
        // row's checkmark or note link still opens the actions.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        // Recognize alongside the scroll view's own pan so a vertical drag
        // keeps scrolling; the axis lock keeps us from fighting it.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
