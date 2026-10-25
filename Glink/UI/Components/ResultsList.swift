import SwiftUI

/// Grouped result rows with a selection highlight that slides between rows.
struct ResultsList: View {
    let model: PanelViewModel
    let sections: [ResultSection]
    /// When set, image thumbnails publish their frames so a preview can zoom out of them.
    var thumbnailNamespace: Namespace.ID?
    var showsAccessories = true

    @Namespace private var selectionNamespace

    static let calculatorRowHeight: CGFloat = 92
    static let topAnchor = "results-top"

    static func contentHeight(for sections: [ResultSection], scale: CGFloat) -> CGFloat {
        guard !sections.isEmpty else { return 0 }
        var h = Theme.Panel.listPadding * 2
        for (i, s) in sections.enumerated() {
            if s.id != "calculator" { h += Theme.Panel.sectionHeaderHeight + (i == 0 ? 0 : 4) }
            for item in s.items { h += item.kind == .calculator ? calculatorRowHeight : Theme.Panel.rowHeight }
        }
        return h
    }

    var body: some View {
        let indexByID = Dictionary(uniqueKeysWithValues: sections.flatMap(\.items).enumerated().map { ($1.id, $0) })
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                // Lazy: only the ~9 visible rows are built and laid out on each keystroke.
                LazyVStack(spacing: 0) { rows(indexByID) }
                    .padding(Theme.Panel.listPadding)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Results")
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            .scrollContentBackground(.hidden)
            .onChange(of: model.selectedID) { _, id in
                guard let id, model.selectionSource == .keyboard else { return }
                // Selecting the first row reveals its section header too.
                let target = id == sections.first?.items.first?.id ? Self.topAnchor : id
                withAnimation(Motion.resolved(Motion.snappy)) { proxy.scrollTo(target) }
            }
        }
        .motion(Motion.snappy, value: model.selectedID)
        .motion(Motion.gentle, value: model.commandHeld)
    }

    @ViewBuilder
    private func rows(_ indexByID: [String: Int]) -> some View {
        Color.clear.frame(height: 0).id(Self.topAnchor)
        ForEach(Array(sections.enumerated()), id: \.element.id) { sectionIndex, section in
            if section.id != "calculator" {
                SectionHeader(title: section.title)
                    .padding(.top, sectionIndex == 0 ? 0 : 4)
                    .transition(.opacity)
            }
            ForEach(section.items) { item in
                let index = indexByID[item.id] ?? 0
                row(for: item, index: index)
                    .id(item.id)
                    .modifier(StaggerIn(index: index, openCount: model.openCount, openedAt: model.openedAt))
                    .transition(Motion.rowTransition)
            }
        }
    }

    @ViewBuilder
    private func row(for item: SearchItem, index: Int) -> some View {
        let selected = item.id == (model.selectedID ?? sections.first?.items.first?.id)
        Group {
            if item.kind == .calculator, let calc = item.calculation {
                CalculatorRow(calculation: calc, isSelected: selected, namespace: selectionNamespace)
            } else {
                ResultRow(
                    item: item,
                    isSelected: selected,
                    shortcutIndex: model.commandHeld && index < 9 ? index + 1 : nil,
                    showsAccessory: showsAccessories,
                    namespace: selectionNamespace,
                    thumbnailNamespace: thumbnailNamespace
                )
                .equatable()
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase { model.hoverSelect(item.id) }
        }
        .onTapGesture { model.activate(item) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.calculation.map { "\($0.input) equals \($0.result)" } ?? item.title)
        .accessibilityValue([item.subtitle, item.accessory].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(item.primaryAction?.title ?? "")
        .accessibilityIdentifier("result.\(item.id)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.activate(item) }
    }
}

/// Rows cascade in (18 ms apart, max 8) only on panel open — never while typing.
/// Rows stay alive between opens; each open replays the cascade instead of rebuilding the list.
struct StaggerIn: ViewModifier {
    let index: Int
    let openCount: Int
    @State private var shown: Bool

    init(index: Int, openCount: Int, openedAt: Date) {
        self.index = index
        self.openCount = openCount
        // Rows created right after an open (e.g. the first results) join the cascade too.
        let fresh = Date().timeIntervalSince(openedAt) < 0.25 && index < Motion.staggerMaxRows
        _shown = State(initialValue: !fresh)
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .onAppear { if !shown { cascade() } }
            .onChange(of: openCount) {
                guard index < Motion.staggerMaxRows, !Motion.isReduced, !Motion.isOff else { return }
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { shown = false }
                cascade()
            }
    }

    private func cascade() {
        if Motion.isReduced || Motion.isOff {
            shown = true
        } else {
            withAnimation(Motion.smooth.delay(Double(index) * Motion.staggerStep)) { shown = true }
        }
    }
}

/// Equatable so SwiftUI skips rows that didn't change: moving the selection re-renders two rows,
/// not the whole list. (SearchItem holds action closures, which SwiftUI can't compare on its own.)
struct ResultRow: View, Equatable {
    nonisolated static func == (a: ResultRow, b: ResultRow) -> Bool {
        a.item == b.item && a.item.accessory == b.item.accessory && a.item.subtitleHighlight == b.item.subtitleHighlight
            && a.isSelected == b.isSelected
            && a.shortcutIndex == b.shortcutIndex && a.showsAccessory == b.showsAccessory
            && a.namespace == b.namespace && a.thumbnailNamespace == b.thumbnailNamespace
    }

    let item: SearchItem
    let isSelected: Bool
    var shortcutIndex: Int?
    var showsAccessory = true
    let namespace: Namespace.ID
    var thumbnailNamespace: Namespace.ID?

    @State private var hovered = false
    @Environment(\.textScale) private var scale
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                HighlightedText(text: item.title, matched: item.matchedIndices)
                    .font(Typography.rowTitle(scale))
                    .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(Self.highlighted(subtitle, item.subtitleHighlight))
                        .font(Typography.rowSubtitle(scale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: Theme.Panel.rowHeight)
        .background {
            ZStack {
                if hovered && !isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Theme.hoverFill(contrast: contrast))
                        .transition(.opacity)
                }
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Theme.selectionFill(contrast: contrast))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
        }
        .onHover { h in Motion.animate(Motion.gentle) { hovered = h } }
    }

    @ViewBuilder
    private var icon: some View {
        let view = ItemIconView(icon: item.icon, size: 24)
        if let ns = thumbnailNamespace, case .clipboardImage = item.icon {
            view.matchedGeometryEffect(id: "thumb-\(item.id)", in: ns, isSource: true)
        } else {
            view
        }
    }

    static func highlighted(_ text: String, _ word: String?) -> AttributedString {
        var s = AttributedString(text)
        if let word, !word.isEmpty, let r = s.range(of: word, options: .caseInsensitive) {
            s[r].foregroundColor = .primary
            s[r].inlinePresentationIntent = .stronglyEmphasized
        }
        return s
    }

    @ViewBuilder
    private var accessory: some View {
        if item.matchedByMeaning && shortcutIndex == nil {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.purple)
                .help("Matched by meaning")
                .accessibilityLabel("Matched by meaning")
        }
        if let n = shortcutIndex {
            Keycap(text: "⌘\(n)", prominent: isSelected)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
        } else if showsAccessory, let accessory = item.accessory {
            Text(accessory)
                .font(Typography.accessory(scale))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .transition(.opacity)
        }
    }
}

/// Title with fuzzy-matched characters emphasized.
struct HighlightedText: View {
    let text: String
    let matched: [Int]

    var body: some View {
        if matched.isEmpty {
            Text(text)
        } else {
            Text(attributed)
        }
    }

    private var attributed: AttributedString {
        let set = Set(matched)
        var result = AttributedString()
        for (i, ch) in text.enumerated() {
            var piece = AttributedString(String(ch))
            if set.contains(i) {
                piece.font = .system(size: 14, weight: .semibold)
            } else {
                piece.foregroundColor = .primary.opacity(0.88)
            }
            result += piece
        }
        return result
    }
}

/// The calculator's two-card row; the answer's digits roll as it changes.
struct CalculatorRow: View {
    let calculation: CalculationPayload
    let isSelected: Bool
    let namespace: Namespace.ID
    @Environment(\.textScale) private var scale
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 0) {
            card(value: calculation.input, label: "Question", numeric: false)
            Image(systemName: "arrow.right").accessibilityHidden(true)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 36)
            card(value: calculation.result, label: calculation.resultLabel, numeric: true)
        }
        .padding(6)
        .frame(height: ResultsList.calculatorRowHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.row + 2, style: .continuous)
                    .fill(Theme.selectionFill(contrast: contrast))
                    .matchedGeometryEffect(id: "selection", in: namespace)
            }
        }
    }

    private func card(value: String, label: String, numeric: Bool) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(numeric ? Typography.calculator(scale) : .system(size: 18 * scale, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .textSelection(.enabled)
            Text(label)
                .font(.system(size: 11 * scale, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}
