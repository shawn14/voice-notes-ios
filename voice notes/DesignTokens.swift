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
                    .frame(width: EEONLayout.minTarget, height: EEONLayout.minTarget)
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(role.tint)
            }

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
        .padding(.vertical, 4)
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
                .frame(width: EEONLayout.minTarget, height: EEONLayout.minTarget)
            Image(systemName: systemName)
                .font(.body)
                .foregroundStyle(tint)
        }
    }
}
