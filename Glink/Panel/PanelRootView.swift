import SwiftUI

struct PanelRootView: View {
    @Bindable var model: PanelViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var settings: AppSettings { AppSettings.shared }
    private var isOpening: Bool { Date().timeIntervalSince(model.openedAt) < 0.35 }

    var body: some View {
        ZStack(alignment: .top) {
            // Clicks in the transparent margin around the panel dismiss it.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { PanelController.shared.hide() }

            panel
                .frame(width: Theme.Panel.width, height: panelHeight, alignment: .top)
                .onChange(of: panelHeight, initial: true) { _, h in PanelController.shared.lastPanelHeight = h }
                .padding(.top, Theme.Panel.windowMargin)
        }
        .environment(\.textScale, settings.textSize.scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Model state changes plainly; the views declare how each change animates.
        .motion(Motion.smooth, value: model.route)
        .motion(Motion.snappy, value: model.actionsPresented)
        .motion(Motion.snappy, value: model.argumentItem?.id)
        .motion(Motion.gentle, value: model.showSkeleton)
        // While the panel springs in, results appear in place: animating the list (row transitions,
        // height) at the same time forced a full re-layout every frame and caused hitches on open.
        .animation(isOpening ? nil : Motion.resolved(Motion.smooth), value: model.resultsSignature)
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        let moving = !(reduceMotion || settings.animationLevel != .full)
        return VStack(spacing: 0) {
            SearchBar(model: model)
            Divider().opacity(scheme == .dark ? 0.5 : 0.8)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                .overlay {
                    // The list behind the actions panel dims slightly.
                    if model.actionsPresented {
                        Color.black.opacity(scheme == .dark ? 0.22 : 0.08)
                            .contentShape(Rectangle())
                            .onTapGesture { model.closeActions() }
                            .transition(.opacity)
                    }
                }
            FooterBar(model: model)
        }
        .background(PanelBackground(style: settings.windowStyle))
        .overlay(alignment: .bottomTrailing) {
            if model.actionsPresented {
                ActionPanelView(model: model)
                    .padding(.trailing, 8)
                    .padding(.bottom, Theme.Panel.footerHeight + 6)
                    .transition(
                        moving
                            ? .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.98, anchor: .bottomTrailing))
                            : .opacity
                    )
            }
        }
        .clipShape(shape)
        .overlay(GlassEdge())
        // The shadow is cast by a plain shape behind the panel, so animating frames don't have to
        // re-render the whole panel offscreen just to blur its outline.
        .background(
            shape.fill(Color.black.opacity(0.001))
                .shadow(color: .black.opacity(Theme.shadowOpacity(scheme)), radius: 30, y: 14)
        )
        // Entrance and exit are Core Animation springs on the hosting layer (PanelController),
        // so they run in the render server without re-rendering this view every frame.
    }

    @ViewBuilder
    private var content: some View {
        ZStack(alignment: .top) {
            switch model.route {
            case nil:
                rootContent
                    .transition(routeTransition(forward: false))
            case .clipboard:
                ClipboardHistoryView(model: model).transition(routeTransition(forward: true))
            case .ai:
                AIResponseView(model: model).transition(routeTransition(forward: true))
            case .mcpCheck:
                MCPCheckView(model: model).transition(routeTransition(forward: true))
            case .scriptOutput(let output):
                ScriptOutputView(output: output, filter: model.query).transition(routeTransition(forward: true))
            case .snippets:
                SnippetsView(model: model).transition(routeTransition(forward: true))
            }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if let item = model.argumentItem {
            ArgumentHintView(item: item, query: model.query)
        } else if model.showSkeleton || (model.isLoading && model.rootSections.isEmpty) {
            SkeletonList(rows: 5)
                .transition(.opacity)
        } else {
            VStack(spacing: 0) {
                if model.hasWindowCommandsVisible {
                    PermissionCard(feature: "move and resize windows")
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                }
                if model.isFallback {
                    NoResultsHeader(query: model.query)
                        .transition(.opacity)
                }
                ResultsList(model: model, sections: model.sections)
            }
        }
    }

    private func routeTransition(forward: Bool) -> AnyTransition {
        if reduceMotion || settings.animationLevel != .full { return .opacity }
        return .asymmetric(insertion: .push(from: forward ? .trailing : .leading),
                           removal: .push(from: forward ? .leading : .trailing))
    }

    // MARK: Height

    /// The panel grows and shrinks with its results (max 474pt); SwiftUI animates the change.
    private var panelHeight: CGFloat {
        let chrome = Theme.Panel.searchHeight + 1 + Theme.Panel.footerHeight
        guard model.route == nil else { return Theme.Panel.maxHeight }
        if model.argumentItem != nil { return chrome + 150 }
        var list: CGFloat
        if model.showSkeleton || (model.isLoading && model.rootSections.isEmpty) {
            list = 5 * Theme.Panel.rowHeight + Theme.Panel.listPadding * 2
        } else {
            list = ResultsList.contentHeight(for: model.sections, scale: settings.textSize.scale)
            if model.isFallback { list += NoResultsHeader.height }
            if model.hasWindowCommandsVisible && !PermissionsManager.shared.isAccessibilityTrusted { list += PermissionCard.height + 8 }
        }
        var height = min(Theme.Panel.maxHeight, chrome + list)
        // While ⌘K is open, grow so the actions menu is never squeezed by a short result list.
        if model.actionsPresented {
            let menu = ActionPanelView.height(actionCount: model.filteredActions.count)
            height = max(height, min(Theme.Panel.maxHeight, Theme.Panel.searchHeight + 1 + 8 + menu + Theme.Panel.footerHeight + 6))
        }
        return height
    }
}

// MARK: - Argument mode hint

private struct ArgumentHintView: View {
    let item: SearchItem
    let query: String
    @Environment(\.textScale) private var scale

    var body: some View {
        VStack(spacing: 10) {
            ItemIconView(icon: item.icon, size: 36)
                .symbolEffect(.bounce, value: item.id)
            Text(query.isEmpty ? "Type your \(item.argumentPlaceholder?.lowercased() ?? "input")" : "Press ↵ to run “\(item.title)”")
                .font(.system(size: 13 * scale, weight: .medium))
                .contentTransition(.opacity)
            HStack(spacing: 6) {
                Keycap(text: "⌫")
                Text("on an empty field to go back").font(.system(size: 12 * scale)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .motion(Motion.gentle, value: query.isEmpty)
    }
}

// MARK: - No results

struct NoResultsHeader: View {
    static let height: CGFloat = 92
    let query: String
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolEffect(.bounce, value: appeared)
            Text("No results for “\(query)”")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text("Try one of these instead")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .onAppear { appeared.toggle() }
    }
}
