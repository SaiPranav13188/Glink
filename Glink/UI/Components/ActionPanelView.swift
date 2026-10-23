import GlinkCore
import SwiftUI

/// The ⌘K actions menu: slides up from the footer with its own search field.
struct ActionPanelView: View {
    @Bindable var model: PanelViewModel
    @FocusState private var searchFocused: Bool
    @Namespace private var ns
    @Environment(\.colorSchemeContrast) private var contrast

    static let rowHeight: CGFloat = 34
    static let maxListHeight: CGFloat = 260

    /// Full height of the menu for a number of actions; the panel grows to fit it.
    static func height(actionCount: Int) -> CGFloat {
        min(CGFloat(max(actionCount, 1)) * rowHeight + 8, maxListHeight) + 36 + 1 + 30
    }

    var body: some View {
        let actions = model.filteredActions
        VStack(spacing: 0) {
            if let title = model.argumentItem?.title ?? (model.route == nil ? model.selectedItem?.title : model.route?.title) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(actions) { action in
                        actionRow(action, selected: action.id == (model.actionsSelectedID ?? actions.first?.id))
                    }
                    if actions.isEmpty {
                        Text("No matching actions")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(height: 36)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .frame(height: min(CGFloat(max(actions.count, 1)) * Self.rowHeight + 8, Self.maxListHeight))
            .motion(Motion.snappy, value: model.actionsSelectedID)

            Divider()
            TextField("", text: $model.actionsQuery, prompt: Text("Search for actions…").foregroundStyle(.tertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .accessibilityLabel("Search actions")
                .padding(.horizontal, 12)
                .frame(height: 36)
        }
        .frame(width: 320)
        .background(PanelBackground(cornerRadius: 12))
        .overlay(GlassEdge(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .onAppear { searchFocused = true }
    }

    private func actionRow(_ action: ItemAction, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: action.symbol)
                .font(.system(size: 13))
                .frame(width: 18)
                .foregroundStyle(action.style == .destructive ? Color.red : Color.secondary)
                .accessibilityHidden(true)
            Text(action.title)
                .font(.system(size: 13))
                .foregroundStyle(action.style == .destructive ? Color.red : Color.primary)
                .lineLimit(1)
            Spacer()
            if let shortcut = action.shortcut {
                HStack(spacing: 2) {
                    ForEach(Array(shortcut.symbols.enumerated()), id: \.offset) { Keycap(text: $0.element) }
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.selectionFill(contrast: contrast))
                    .matchedGeometryEffect(id: "actionSelection", in: ns)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase, model.actionsSelectedID != action.id { model.actionsSelectedID = action.id }
        }
        .onTapGesture {
            model.actionsSelectedID = action.id
            model.runFromActionsPanel(action)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.shortcut.map { "Shortcut " + $0.symbols.joined() } ?? "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.runFromActionsPanel(action) }
    }
}

extension PanelViewModel {
    func runFromActionsPanel(_ action: ItemAction) {
        if action.id == "runArgument" {
            closeActions()
            submitArgument()
        } else {
            run(action, for: route == nil ? selectedItem : nil)
        }
    }
}
