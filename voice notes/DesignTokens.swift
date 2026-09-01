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

// MARK: - Swipe delete

/// Swipe-delete for custom ScrollView/LazyVStack rows. Native
/// `.swipeActions` only works reliably in `List`; Home uses custom stacks so
/// it needs this wrapper to make the same gesture available there too.
struct EEONSwipeDeleteRow<Content: View>: View {
    var label: String = "Delete"
    var cornerRadius: CGFloat = EEONLayout.cardRadius
    var background: Color = .eeonCard
    let onDelete: () -> Void
    let content: Content

    @State private var offset: CGFloat = 0
    @State private var isOpen = false

    private let actionWidth: CGFloat = 86

    init(
        label: String = "Delete",
        cornerRadius: CGFloat = EEONLayout.cardRadius,
        background: Color = .eeonCard,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.cornerRadius = cornerRadius
        self.background = background
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < -1 || isOpen {
                Button(role: .destructive) {
                    delete()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.body.weight(.semibold))
                        Text(label)
                            .font(EEONType.badge)
                    }
                    .foregroundStyle(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(background)
                .offset(x: offset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: offset)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let base = isOpen ? -actionWidth : 0
                offset = max(-actionWidth, min(0, base + value.translation.width))
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    settle(open: isOpen)
                    return
                }

                let base = isOpen ? -actionWidth : 0
                let projected = base + value.predictedEndTranslation.width
                if projected < -actionWidth * 1.45 {
                    delete()
                } else {
                    settle(open: offset < -actionWidth * 0.45)
                }
            }
    }

    private func settle(open: Bool) {
        isOpen = open
        offset = open ? -actionWidth : 0
    }

    private func delete() {
        isOpen = false
        offset = 0
        onDelete()
    }
}
