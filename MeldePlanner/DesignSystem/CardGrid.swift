import SwiftUI
import UniformTypeIdentifiers

/// How many grid columns a card spans.
private nonisolated struct CardSpanKey: LayoutValueKey {
    static let defaultValue = 1
}

/// Packs cards into rows like tiles on a console home screen. A card that
/// doesn't fit starts a new row; the last card of a row stretches to close the
/// gap. Cards in a row share the tallest card's height.
struct CardGridLayout: Layout {
    var columns: Int
    var spacing: CGFloat

    private struct Row {
        var items: [(index: Int, span: Int)] = []
        var used = 0
    }

    private func rows(_ subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let span = min(max(subview[CardSpanKey.self], 1), columns)
            if row.used + span > columns, !row.items.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.items.append((index, span))
            row.used += span
        }
        if !row.items.isEmpty { rows.append(row) }
        // Stretch the last card so a row never ends with a gap.
        for i in rows.indices where rows[i].used < columns {
            let last = rows[i].items.count - 1
            rows[i].items[last].span += columns - rows[i].used
            rows[i].used = columns
        }
        return rows
    }

    private func columnWidth(_ width: CGFloat) -> CGFloat {
        (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    private func width(span: Int, column: CGFloat) -> CGFloat {
        column * CGFloat(span) + spacing * CGFloat(span - 1)
    }

    private func height(_ row: Row, _ subviews: Subviews, column: CGFloat) -> CGFloat {
        row.items.map { item in
            subviews[item.index].sizeThatFits(ProposedViewSize(width: width(span: item.span, column: column), height: nil)).height
        }.max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 360
        let column = columnWidth(total)
        let rows = rows(subviews)
        let heights = rows.map { height($0, subviews, column: column) }
        let sum = heights.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: total, height: sum)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let column = columnWidth(bounds.width)
        var y = bounds.minY
        for row in rows(subviews) {
            let rowHeight = height(row, subviews, column: column)
            var x = bounds.minX
            for item in row.items {
                let w = width(span: item.span, column: column)
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: w, height: rowHeight)
                )
                x += w + spacing
            }
            y += rowHeight + spacing
        }
    }
}

extension CardSize {
    /// Columns a card spans: two columns on iPhone, four on iPad.
    func span(columns: Int) -> Int {
        switch self {
        case .small: 1
        case .medium: columns >= 4 ? 2 : columns
        case .large: columns
        }
    }

    var title: String {
        switch self {
        case .small: L("Klein")
        case .medium: L("Mittel")
        case .large: L("Groß")
        }
    }
}

/// Cards the student arranges like widgets: in edit mode (the "Anpassen"
/// button, or a long press on a card) cards wiggle, can be dragged to a new
/// place (the others move aside live), resized by dragging the corner handle,
/// and hidden. Hidden cards wait in a tray below to be added back.
struct CustomizableCardGrid<Kind, Content: View>: View
where Kind: Codable & Hashable & Sendable & CaseIterable & RawRepresentable, Kind.RawValue == String {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var slots: [CardSlot<Kind>]
    @Binding var editing: Bool
    var title: (Kind) -> String
    var symbol: (Kind) -> String
    var save: ([CardSlot<Kind>]) -> Void
    @ViewBuilder var content: (Kind, CardSize) -> Content

    /// The order while a card is being dragged; saved when it's dropped.
    @State private var liveOrder: [CardSlot<Kind>]?
    @State private var dragging: Kind?
    @State private var feedback = 0

    private var columns: Int { sizeClass == .regular ? 4 : 2 }
    private var shown: [CardSlot<Kind>] { liveOrder ?? slots }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.spacingL) {
            CardGridLayout(columns: columns, spacing: DS.spacingL) {
                ForEach(shown, id: \.kind) { slot in
                    card(slot)
                        .layoutValue(key: CardSpanKey.self, value: slot.size.span(columns: columns))
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2), value: shown)
            if shown.isEmpty && !editing {
                ContentUnavailableView {
                    Label(L("Alle Karten ausgeblendet"), systemImage: "square.grid.2x2")
                } actions: {
                    Button(L("Karten hinzufügen")) {
                        withAnimation { editing = true }
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            if editing {
                hiddenCards
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        // A card dropped between cards still ends the drag.
        .onDrop(of: [.text], delegate: GridDropDelegate(onFinish: { finishDrag() }))
        .sensoryFeedback(.selection, trigger: feedback)
        .onChange(of: editing) { _, now in
            if !now { finishDrag() }
        }
    }

    @ViewBuilder
    private func card(_ slot: CardSlot<Kind>) -> some View {
        let base = content(slot.kind, slot.size)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        if editing {
            base
                .allowsHitTesting(false)
                .overlay { editChrome(slot) }
                .opacity(dragging == slot.kind ? 0.4 : 1)
                .modifier(Wiggle(active: !reduceMotion))
                // The whole card can be grabbed, not just its buttons.
                .contentShape([.interaction, .dragPreview], .rect(cornerRadius: DS.cardRadius))
                .onDrag {
                    dragging = slot.kind
                    liveOrder = slots
                    return NSItemProvider(object: slot.kind.rawValue as NSString)
                }
                .onDrop(of: [.text], delegate: CardDropDelegate(
                    target: slot.kind,
                    dragging: $dragging,
                    order: $liveOrder,
                    onMove: { feedback += 1 },
                    onFinish: { finishDrag() }
                ))
        } else {
            base
                .onLongPressGesture(minimumDuration: 0.6) {
                    feedback += 1
                    withAnimation(.spring(duration: 0.3)) { editing = true }
                }
        }
    }

    /// Dashed outline, remove button and corner handle for resizing.
    private func editChrome(_ slot: CardSlot<Kind>) -> some View {
        RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .overlay(alignment: .topLeading) {
                Button(L("Ausblenden"), systemImage: "minus") { hide(slot.kind) }
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.bold))
                    .frame(width: 30, height: 30)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .padding(-6)
            }
            .overlay(alignment: .bottomTrailing) {
                ResizeHandle(size: slot.size) { size in
                    resize(slot.kind, to: size)
                    feedback += 1
                }
                .padding(DS.spacingXS)
            }
            .overlay(alignment: .topTrailing) {
                Menu {
                    Picker(L("Größe"), selection: Binding(get: { slot.size }, set: { resize(slot.kind, to: $0) })) {
                        ForEach(CardSize.allCases) { Text($0.title).tag($0) }
                    }
                    Button(L("Nach vorne"), systemImage: "arrow.up.left") { shift(slot.kind, by: -1) }
                    Button(L("Nach hinten"), systemImage: "arrow.down.right") { shift(slot.kind, by: 1) }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(L("Größe und Position"))
                .padding(DS.spacingS)
            }
    }

    @ViewBuilder
    private var hiddenCards: some View {
        let hidden = Array(Kind.allCases).filter { kind in !slots.contains { $0.kind == kind } }
        if !hidden.isEmpty {
            VStack(alignment: .leading, spacing: DS.spacingS) {
                Text(L("Weitere Karten"))
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DS.spacingS)], spacing: DS.spacingS) {
                    ForEach(hidden, id: \.self) { kind in
                        Button {
                            feedback += 1
                            save(slots + [CardSlot(kind: kind, size: .medium)])
                        } label: {
                            Label(title(kind), systemImage: symbol(kind))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(DS.spacingM)
                        }
                        .buttonStyle(.plain)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.rowRadius))
                        .overlay(alignment: .trailing) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.accentColor)
                                .padding(.trailing, DS.spacingM)
                        }
                    }
                }
            }
        }
    }

    private func finishDrag() {
        if let order = liveOrder, order != slots { save(order) }
        liveOrder = nil
        dragging = nil
    }

    private func resize(_ kind: Kind, to size: CardSize) {
        var list = slots
        guard let i = list.firstIndex(where: { $0.kind == kind }) else { return }
        list[i].size = size
        save(list)
    }

    private func shift(_ kind: Kind, by delta: Int) {
        var list = slots
        guard let i = list.firstIndex(where: { $0.kind == kind }) else { return }
        let target = min(max(i + delta, 0), list.count - 1)
        list.swapAt(i, target)
        save(list)
    }

    private func hide(_ kind: Kind) {
        feedback += 1
        save(slots.filter { $0.kind != kind })
    }
}

/// Reorders while a card is dragged over others, like app icons on the Home Screen.
private struct CardDropDelegate<Kind: Codable & Hashable & Sendable>: DropDelegate {
    let target: Kind
    @Binding var dragging: Kind?
    @Binding var order: [CardSlot<Kind>]?
    var onMove: () -> Void
    var onFinish: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target, var list = order,
              let from = list.firstIndex(where: { $0.kind == dragging }),
              let to = list.firstIndex(where: { $0.kind == target }) else { return }
        let slot = list.remove(at: from)
        list.insert(slot, at: to)
        order = list
        onMove()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onFinish()
        return true
    }
}

/// Ends a drag that was dropped on the grid but not on a card.
private struct GridDropDelegate: DropDelegate {
    var onFinish: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onFinish()
        return true
    }
}

/// Drag the corner to make a card bigger or smaller, one size step per ~70 points.
private struct ResizeHandle: View {
    let size: CardSize
    var onResize: (CardSize) -> Void
    @State private var applied = 0

    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.footnote.weight(.bold))
            .frame(width: 34, height: 34)
            .glassEffect(.regular.interactive(), in: .circle)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        let steps = Int(((value.translation.width + value.translation.height) / 2 / 70).rounded(.towardZero))
                        guard steps != applied else { return }
                        let all = CardSize.allCases
                        let current = all.firstIndex(of: size) ?? 0
                        let next = min(max(current + steps - applied, 0), all.count - 1)
                        applied = steps
                        if all[next] != size { onResize(all[next]) }
                    }
                    .onEnded { _ in applied = 0 }
            )
            .accessibilityLabel(L("Größe ändern"))
            .accessibilityValue(size.title)
            .accessibilityAdjustableAction { direction in
                let all = CardSize.allCases
                let current = all.firstIndex(of: size) ?? 0
                switch direction {
                case .increment: if current + 1 < all.count { onResize(all[current + 1]) }
                case .decrement: if current > 0 { onResize(all[current - 1]) }
                @unknown default: break
                }
            }
    }
}

/// The gentle wiggle of cards in edit mode. Always the same view structure,
/// so turning it off doesn't rebuild the card (and reset its state).
private struct Wiggle: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content.phaseAnimator([-1.0, 1.0]) { view, phase in
            view.rotationEffect(.degrees(active ? phase * 0.6 : 0))
        } animation: { _ in
            .easeInOut(duration: 0.16)
        }
    }
}

/// The toolbar button that switches a card screen into edit mode.
struct CustomizeButton: View {
    @Binding var editing: Bool

    var body: some View {
        Button(editing ? L("Fertig") : L("Anpassen"), systemImage: editing ? "checkmark" : "square.grid.2x2") {
            withAnimation { editing.toggle() }
        }
    }
}
