//
//  MindMapView.swift
//  voice notes
//
//  Per-note mind map sheet (note ⋯ → Mind Map). Left-to-right tree drawn as
//  text joined by curves, no boxed nodes (brain rule #41). Branch titles
//  are buttons that fold their leaves. Fitted to the width, never panned: on
//  a phone the root sits on top and branches hang below it (a left-to-right
//  tree cut every leaf off at 390-440 pt, simulator screenshot 2026-09-25);
//  wide screens get the classic left-to-right layout.
//

import SwiftUI

struct MindMapView: View {
    let note: Note

    @Environment(\.dismiss) private var dismiss
    @State private var map: NoteMindMapNode?
    @State private var error: String?
    @State private var isLoading = false
    @State private var collapsed: Set<Int> = []

    /// The text the map is built from: the cleaned-up note when there is one.
    private var sourceText: String { Self.sourceText(for: note) }

    /// Shared with NoteDetailView so its "Mind map" line finds the same cache entry.
    static func sourceText(for note: Note) -> String {
        note.enhancedNoteText ?? note.transcript ?? note.content
    }

    var body: some View {
        NavigationStack {
            Group {
                if let map {
                    GeometryReader { proxy in
                        ScrollView(.vertical) {
                            tree(map, width: proxy.size.width - 48)
                                .padding(24)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                } else if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Mapping this note…")
                            .font(.subheadline)
                            .foregroundStyle(.eeonTextSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView {
                        Label("No Mind Map", systemImage: "point.3.connected.trianglepath.dotted")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { load(force: true) }
                            .buttonStyle(.borderedProminent)
                            .tint(.eeonAccent)
                    }
                }
            }
            .background(Color.eeonBackground)
            .navigationTitle("Mind Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if map != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                load(force: true)
                            } label: {
                                Label("Regenerate", systemImage: "arrow.clockwise")
                            }
                            ShareLink(item: outline, subject: Text(map?.title ?? "Mind Map")) {
                                Label("Share as Outline", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Mind map options")
                    }
                }
            }
        }
        .task { load(force: false) }
    }

    // MARK: Tree

    private static let branchWidth: CGFloat = 120
    private static let wideRootWidth: CGFloat = 150
    private static let wideLayoutMinWidth: CGFloat = 640

    private func tree(_ root: NoteMindMapNode, width: CGFloat) -> some View {
        let wide = width >= Self.wideLayoutMinWidth
        // Phone: root on top, branches indented below it.
        let indent: CGFloat = wide ? 0 : 20
        let rowSpacing: CGFloat = 20
        let used = (wide ? Self.wideRootWidth + 36 : indent) + Self.branchWidth + rowSpacing
        let leafWidth = max(width - used, 120)

        let rootTitle = Text(root.title)
            .font(.title3.weight(.bold))
            .foregroundStyle(.eeonTextPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: wide ? Self.wideRootWidth : width, alignment: .leading)
            .anchorPreference(key: NodeAnchors.self, value: .bounds) { ["root": $0] }

        let branches = VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(root.children.enumerated()), id: \.offset) { index, branch in
                HStack(alignment: .center, spacing: rowSpacing) {
                    Button {
                        withAnimation(.snappy) {
                            if collapsed.contains(index) { collapsed.remove(index) } else { collapsed.insert(index) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(branch.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.eeonAccent)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if !branch.children.isEmpty {
                                Image(systemName: collapsed.contains(index) ? "chevron.right" : "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.eeonTextTertiary)
                            }
                        }
                        .frame(width: Self.branchWidth, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(collapsed.contains(index) ? "Shows details" : "Hides details")
                    .anchorPreference(key: NodeAnchors.self, value: .bounds) { ["b\(index)": $0] }

                    if !collapsed.contains(index) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(branch.children.enumerated()), id: \.offset) { leafIndex, leaf in
                                Text(leaf.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.eeonTextPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: leafWidth, alignment: .leading)
                                    .anchorPreference(key: NodeAnchors.self, value: .bounds) {
                                        ["b\(index)l\(leafIndex)": $0]
                                    }
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
        }

        return Group {
            if wide {
                HStack(alignment: .center, spacing: 36) { rootTitle; branches }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    rootTitle
                    branches.padding(.leading, indent)
                }
            }
        }
        .backgroundPreferenceValue(NodeAnchors.self) { anchors in
            GeometryReader { proxy in
                connectors(root, anchors: anchors, proxy: proxy, wide: wide)
            }
        }
    }

    private func connectors(_ root: NoteMindMapNode, anchors: [String: Anchor<CGRect>], proxy: GeometryProxy, wide: Bool) -> some View {
        Path { path in
            func link(_ from: String, _ to: String) {
                guard let a = anchors[from], let b = anchors[to] else { return }
                // Phone layout: the root sits above, so its links drop from
                // under the title's left edge and elbow into each branch.
                if !wide && from == "root" {
                    let start = CGPoint(x: proxy[a].minX + 6, y: proxy[a].maxY + 6)
                    let end = CGPoint(x: proxy[b].minX - 6, y: proxy[b].midY)
                    path.move(to: start)
                    path.addCurve(to: end, control1: CGPoint(x: start.x, y: end.y), control2: CGPoint(x: start.x, y: end.y))
                    return
                }
                let start = CGPoint(x: proxy[a].maxX + 6, y: proxy[a].midY)
                let end = CGPoint(x: proxy[b].minX - 6, y: proxy[b].midY)
                let bend = (end.x - start.x) * 0.5
                path.move(to: start)
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: start.x + bend, y: start.y),
                    control2: CGPoint(x: end.x - bend, y: end.y)
                )
            }
            for (index, branch) in root.children.enumerated() {
                link("root", "b\(index)")
                guard !collapsed.contains(index) else { continue }
                for leafIndex in branch.children.indices {
                    link("b\(index)", "b\(index)l\(leafIndex)")
                }
            }
        }
        .stroke(Color.eeonDivider, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    // MARK: Data

    private var outline: String {
        guard let map else { return "" }
        var lines = [map.title]
        for branch in map.children {
            lines.append("- \(branch.title)")
            lines += branch.children.map { "  - \($0.title)" }
        }
        return lines.joined(separator: "\n")
    }

    private func load(force: Bool) {
        let text = sourceText
        if !force, let hit = MindMapService.cached(noteID: note.id, text: text) {
            map = hit
            return
        }
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            error = "Mind maps aren't available right now."
            return
        }
        error = nil
        isLoading = true
        map = nil
        Task {
            do {
                let result = try await MindMapService.mindMap(
                    noteID: note.id, text: text, apiKey: apiKey, forceRefresh: force
                )
                map = result
                collapsed = []
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}

private struct NodeAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}
