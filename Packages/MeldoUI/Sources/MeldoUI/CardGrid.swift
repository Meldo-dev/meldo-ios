import MeldoKit
import MeldoState
import SwiftUI
import UIKit

/// How many grid columns a card spans.
private nonisolated struct CardSpanKey: LayoutValueKey {
    static let defaultValue = 1
}

/// Packs cards into rows like tiles on a console home screen. A card that
/// doesn't fit starts a new row; the last card of a row stretches to close the
/// gap. Cards in a row share the tallest card's height.
public struct CardGridLayout: Layout {
    public var columns: Int
    public var spacing: CGFloat

    public init(columns: Int, spacing: CGFloat) {
        self.columns = columns
        self.spacing = spacing
    }

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

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 360
        let column = columnWidth(total)
        let rows = rows(subviews)
        let heights = rows.map { height($0, subviews, column: column) }
        let sum = heights.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: total, height: sum)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
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
    public func span(columns: Int) -> Int {
        switch self {
        case .small: 1
        case .medium: columns >= 4 ? 2 : columns
        case .large: columns
        }
    }

    public var title: String {
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
public struct CustomizableCardGrid<Kind, Content: View>: View
where Kind: Codable & Hashable & Sendable & CaseIterable & RawRepresentable, Kind.RawValue == String {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public var slots: [CardSlot<Kind>]
    @Binding public var editing: Bool
    public var title: (Kind) -> String
    public var symbol: (Kind) -> String
    public var save: ([CardSlot<Kind>]) -> Void
    @ViewBuilder public var content: (Kind, CardSize) -> Content
    /// The cards this build can show; the tray only offers these.
    public var available: [Kind]

    public init(slots: [CardSlot<Kind>], available: [Kind] = Array(Kind.allCases), editing: Binding<Bool>,
                title: @escaping (Kind) -> String, symbol: @escaping (Kind) -> String,
                save: @escaping ([CardSlot<Kind>]) -> Void, @ViewBuilder content: @escaping (Kind, CardSize) -> Content) {
        self.slots = slots
        self.available = available
        self._editing = editing
        self.title = title
        self.symbol = symbol
        self.save = save
        self.content = content
    }

    /// The order while a card is being dragged; saved when it's dropped.
    @State private var liveOrder: [CardSlot<Kind>]?
    @State private var dragging: Kind?
    /// The card the finger was over last, so a card is only moved once per entry.
    @State private var hovered: Kind?
    /// Finger position, and where on the card it grabbed, in grid coordinates.
    @State private var pointer = CGPoint.zero
    @State private var grab = CGSize.zero
    /// Size of the lifted card when it was picked up.
    @State private var lifted = CGSize.zero
    /// True while a dropped card flies back into its slot.
    @State private var settling = false
    /// Laid-out card frames in grid coordinates, for hit testing while dragging.
    @State private var frames: [Kind: CGRect] = [:]
    @State private var feedback = 0

    private var columns: Int { sizeClass == .regular ? 4 : 2 }
    private var shown: [CardSlot<Kind>] { liveOrder ?? slots }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.spacingL) {
            CardGridLayout(columns: columns, spacing: DS.spacingL) {
                ForEach(shown, id: \.kind) { slot in
                    card(slot)
                        .layoutValue(key: CardSpanKey.self, value: slot.size.span(columns: columns))
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2), value: shown)
            .overlay(alignment: .topLeading) { liftedCard }
            .coordinateSpace(.named(gridSpace))
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
                // The whole card can be grabbed. The edit controls go on top afterwards, so a
                // touch on the resize handle or the remove button never lifts the card.
                .contentShape(.rect(cornerRadius: DS.cardRadius))
                .gesture(LiftGesture(space: gridSpace) { state, point in lift(slot.kind, state, at: point) })
                .overlay { editChrome(slot) }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(gridSpace)) } action: {
                    frames[slot.kind] = $0
                }
                .modifier(Wiggle(active: !reduceMotion && dragging != slot.kind))
                // Its slot stays empty while the lifted copy follows the finger.
                .opacity(dragging == slot.kind ? 0 : 1)
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
                ResizeHandle(
                    size: slot.size,
                    onResize: { size in
                        resize(slot.kind, to: size)
                        feedback += 1
                    },
                    onShift: { shift(slot.kind, by: $0) }
                )
            }
    }

    @ViewBuilder
    private var hiddenCards: some View {
        let hidden = available.filter { kind in !slots.contains { $0.kind == kind } }
        if !hidden.isEmpty {
            VStack(alignment: .leading, spacing: DS.spacingS) {
                Text(L("Weitere Karten"))
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DS.spacingS)], spacing: DS.spacingS) {
                    ForEach(hidden, id: \.self) { kind in
                        // The whole tile is the button: a plain button only takes taps on its
                        // drawn pixels, and an overlay on top of it swallowed taps on the plus.
                        Button {
                            feedback += 1
                            save(slots + [CardSlot(kind: kind, size: .medium)])
                        } label: {
                            HStack(spacing: DS.spacingS) {
                                Label(title(kind), symbol: symbol(kind))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                            }
                            .padding(DS.spacingM)
                            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.rowRadius))
                            .contentShape(.rect(cornerRadius: DS.rowRadius))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var gridSpace: String { "cardGrid" }

    /// The card being moved, drawn above the grid exactly where the finger holds it.
    @ViewBuilder
    private var liftedCard: some View {
        if let kind = dragging, let slot = shown.first(where: { $0.kind == kind }) {
            let target = frames[kind] ?? .zero
            let size = settling ? target.size : lifted
            content(kind, slot.size)
                .frame(width: size.width, height: size.height, alignment: .top)
                .overlay { editChrome(slot) }
                .allowsHitTesting(false)
                .scaleEffect(settling ? 1 : 1.04)
                .shadow(color: .black.opacity(settling ? 0 : 0.3), radius: 16, y: 8)
                .offset(settling
                    ? CGSize(width: target.minX, height: target.minY)
                    : CGSize(width: pointer.x - grab.width, height: pointer.y - grab.height))
                .transition(.identity)
        }
    }

    private func lift(_ kind: Kind, _ state: UIGestureRecognizer.State, at point: CGPoint) {
        switch state {
        case .began:
            guard dragging == nil, let frame = frames[kind] else { return }
            grab = CGSize(width: point.x - frame.minX, height: point.y - frame.minY)
            lifted = frame.size
            pointer = point
            liveOrder = slots
            hovered = nil
            settling = false
            feedback += 1
            dragging = kind
        case .changed:
            guard dragging == kind, !settling else { return }
            pointer = point
            move(kind, over: point)
        default:
            guard dragging == kind else { return }
            finishDrag()
        }
    }

    /// Entering another card moves the dragged one to its place, like app icons on the Home Screen.
    private func move(_ kind: Kind, over point: CGPoint) {
        let over = shown.first { $0.kind != kind && frames[$0.kind]?.contains(point) == true }?.kind
        guard over != hovered else { return }
        hovered = over
        guard let over, var list = liveOrder,
              let from = list.firstIndex(where: { $0.kind == kind }),
              let to = list.firstIndex(where: { $0.kind == over }) else { return }
        list.insert(list.remove(at: from), at: to)
        liveOrder = list
        feedback += 1
    }

    private func finishDrag() {
        if let order = liveOrder, order != slots { save(order) }
        liveOrder = nil
        hovered = nil
        guard dragging != nil, !settling else { return }
        // The lifted card flies into its slot, then the slot shows the card again.
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)) {
            settling = true
        } completion: {
            dragging = nil
            settling = false
        }
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

/// Moving a card starts with a UIKit long press, so the scroll view keeps working: a finger
/// that moves right away scrolls the page, one that rests a moment lifts the card. Locations
/// are reported in the grid's coordinate space.
private struct LiftGesture: UIGestureRecognizerRepresentable {
    var space: String
    var onChange: (UIGestureRecognizer.State, CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.2
        recognizer.allowableMovement = 12
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        onChange(recognizer.state, context.converter.location(in: .named(space)))
    }
}

/// The grey handle in a card's bottom corner. Drag it out or in to make the card bigger
/// or smaller, like a widget on the Home Screen: the card snaps to the next size about
/// every 60 points. A tap steps through the sizes.
private struct ResizeHandle: View {
    let size: CardSize
    var onResize: (CardSize) -> Void
    var onShift: (Int) -> Void
    /// The size when the drag began; the drag distance picks a size relative to it.
    @State private var start: CardSize?

    private let all = CardSize.allCases

    var body: some View {
        CornerArc(radius: DS.cardRadius - 6, inset: 6)
            .stroke(Color(.systemGray), style: StrokeStyle(lineWidth: start == nil ? 5 : 6.5, lineCap: .round))
            .frame(width: 44, height: 44)
            .contentShape(.rect)
            .animation(.spring(duration: 0.2), value: start)
            .onTapGesture(perform: cycle)
            // Global coordinates: the handle moves with the card while it resizes.
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        let from = start ?? size
                        if start == nil { start = size }
                        let reach = (value.translation.width + value.translation.height) / 2
                        let steps = Int((reach / 60).rounded(.towardZero))
                        let index = min(max((all.firstIndex(of: from) ?? 0) + steps, 0), all.count - 1)
                        if all[index] != size { onResize(all[index]) }
                    }
                    .onEnded { _ in start = nil }
            )
            .accessibilityElement()
            .accessibilityLabel(L("Größe ändern"))
            .accessibilityValue(size.title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { cycle() }
            .accessibilityAdjustableAction { direction in
                let current = all.firstIndex(of: size) ?? 0
                switch direction {
                case .increment: if current + 1 < all.count { onResize(all[current + 1]) }
                case .decrement: if current > 0 { onResize(all[current - 1]) }
                @unknown default: break
                }
            }
            // Moving a card by dragging it isn't available to VoiceOver.
            .accessibilityAction(named: L("Nach vorne")) { onShift(-1) }
            .accessibilityAction(named: L("Nach hinten")) { onShift(1) }
    }

    private func cycle() {
        let current = all.firstIndex(of: size) ?? 0
        onResize(all[(current + 1) % all.count])
    }
}

/// A rounded corner stroke that follows the card's bottom-trailing corner.
private struct CornerArc: Shape {
    var radius: CGFloat
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let right = rect.maxX - inset
        let bottom = rect.maxY - inset
        let center = CGPoint(x: right - radius, y: bottom - radius)
        let tail = radius * 0.45
        var path = Path()
        path.move(to: CGPoint(x: right, y: center.y - tail))
        path.addLine(to: CGPoint(x: right, y: center.y))
        path.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: center.x - tail, y: bottom))
        return path
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
public struct CustomizeButton: View {
    @Binding public var editing: Bool

    public init(editing: Binding<Bool>) {
        self._editing = editing
    }

    public var body: some View {
        Button(editing ? L("Fertig") : L("Anpassen"), systemImage: editing ? "checkmark" : "square.grid.2x2") {
            withAnimation { editing.toggle() }
        }
    }
}
