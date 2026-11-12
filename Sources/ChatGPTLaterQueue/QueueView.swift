import AppKit
import SwiftUI

struct QueueRowFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Eager layout keeps every slot measurable, including cards below the scroll viewport.
private struct ParkingGrid: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 392, height: CGFloat((subviews.count + 1) / 2) * 98 - 10)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = (bounds.width - 10) / 2
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index % 2) * (width + 10),
                                     y: bounds.minY + CGFloat(index / 2) * 98),
                          proposal: ProposedViewSize(width: width, height: 88))
        }
    }
}

private struct ParkingStop: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.77, blue: 0.38),
                                          Color(red: 0.76, green: 0.52, blue: 0.20)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                Canvas { context, size in
                    for x in stride(from: -8.0, through: size.width, by: 14.0) {
                        var stripe = Path()
                        stripe.move(to: CGPoint(x: x + 6, y: 0))
                        stripe.addLine(to: CGPoint(x: x + 13, y: 0))
                        stripe.addLine(to: CGPoint(x: x + 7, y: size.height))
                        stripe.addLine(to: CGPoint(x: x, y: size.height))
                        stripe.closeSubpath()
                        context.fill(stripe, with: .color(Color(white: 0.19)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .frame(width: 40, height: 6)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

private struct ParkingBay: View {
    var empty = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.laterInk.opacity(empty ? 0.008 : 0.015))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.laterInk.opacity(empty ? 0.09 : 0.17), lineWidth: 1)
            }
            .overlay {
                if empty {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.laterInk.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .padding(6)
                    Text("P")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.laterInk.opacity(0.20))
                        .frame(width: 24, height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.laterInk.opacity(0.16)))
                }
            }
            .overlay(alignment: .top) { ParkingStop().offset(y: -3) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct QueueView: View {
    @ObservedObject var coordinator: QueueCoordinator
    @ObservedObject var store: LaterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragStartFrame: CGRect?
    @State private var dragTranslation = CGSize.zero
    @State private var hoveredHandleID: UUID?

    init(coordinator: QueueCoordinator) {
        self.coordinator = coordinator
        self.store = coordinator.store
    }

    // Show a glimpse of available spaces without filling the panel with unused capacity.
    private var emptySpaces: Int { min(max(store.cardLimit - store.count, 0), 2) }

    static func boardHeight(for count: Int, limit: Int) -> CGFloat {
        let spaces = count + min(max(limit - count, 0), 2)
        return min(CGFloat((spaces + 1) / 2) * 98 + 18, 420)
    }

    var body: some View {
        if store.items.isEmpty {
            VStack(spacing: 10) {
                Text("All caught up.").font(.system(size: 17, weight: .medium))
                Text("Press ⌃⌥L in ChatGPT\nto save a conversation for later.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).frame(height: 118)
        } else {
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    ParkingGrid {
                        ForEach(0..<(store.count + emptySpaces), id: \.self) { index in
                            ParkingBay(empty: index >= store.count)
                        }
                    }
                    .padding(14)

                    ParkingGrid {
                        ForEach(coordinator.reorderPreview ?? store.items) { item in
                            cardContents(item)
                                .opacity(coordinator.draggingID == item.id ? 0.15 : 1)
                                .zIndex(hoveredHandleID == item.id ? 1 : 0)
                                .background(GeometryReader { proxy in
                                    Color.clear.preference(key: QueueRowFrames.self,
                                        value: [item.id: proxy.frame(in: .named("laterQueue"))])
                                })
                        }
                        ForEach(0..<emptySpaces, id: \.self) { _ in
                            Color.clear.allowsHitTesting(false)
                        }
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: coordinator.reorderPreview?.map(\.id))
                    .padding(14)
                }
                .overlay(alignment: .topLeading) {
                    if let id = coordinator.draggingID,
                       let item = store.items.first(where: { $0.id == id }), let frame = dragStartFrame {
                        cardContents(item)
                            .frame(width: frame.width, height: frame.height)
                            .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                            .position(x: frame.midX + dragTranslation.width, y: frame.midY + dragTranslation.height)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .coordinateSpace(name: "laterQueue")
            }
            .onPreferenceChange(QueueRowFrames.self) { coordinator.rowFrames = $0 }
            .onChange(of: coordinator.draggingID) { id in
                if id == nil { dragStartFrame = nil; dragTranslation = .zero }
            }
            .frame(height: Self.boardHeight(for: store.count, limit: store.cardLimit))
        }
    }

    private func cardContents(_ item: LaterItem) -> some View {
        let hovered = coordinator.hoveredRowID == item.id && coordinator.draggingID == nil
        let dragging = coordinator.draggingID == item.id
        return Button { coordinator.open(item) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Spacer().frame(height: 22)
                Text(item.title)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).accessibilityLabel("Open \(item.title)")
        .overlay(alignment: .topLeading) {
            Button { coordinator.done(item) } label: {
                Image(systemName: "circle").font(.system(size: 18)).foregroundStyle(Color.laterAccent)
                    .frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Mark done")
            .padding(3)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 30, height: 30).contentShape(Rectangle())
                .opacity((hovered || dragging) ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
                .accessibilityLabel("Drag to reorder")
                .onHover { inside in hoveredHandleID = inside ? item.id : nil }
                .overlay(alignment: .trailing) {
                    if hoveredHandleID == item.id && !dragging {
                        Text("Drag to reorder")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.laterInk)
                            .fixedSize()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.laterSeparator, lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                            .offset(x: -32)
                            .allowsHitTesting(false)
                    }
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .named("laterQueue"))
                        .onChanged { value in
                            if dragStartFrame == nil { dragStartFrame = coordinator.rowFrames[item.id] }
                            dragTranslation = value.translation
                            guard let frame = dragStartFrame else { return }
                            NSCursor.closedHand.set()
                            coordinator.updateReorder(item.id, at: CGPoint(
                                x: frame.midX + value.translation.width,
                                y: frame.midY + value.translation.height))
                        }
                        .onEnded { _ in
                            coordinator.finishReorder()
                            dragStartFrame = nil
                            dragTranslation = .zero
                            NSCursor.arrow.set()
                        }
                )
                .padding(3)
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(dragging ? Color.laterElevated : Color.laterElevated.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.laterAccent.opacity(hovered ? 0.09 : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(hovered || dragging ? Color.laterAccent.opacity(0.65) : Color.laterInk.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
                .allowsHitTesting(false)
        }
        .padding(6)
        .onHover { inside in
            if inside { coordinator.hoveredRowID = item.id }
            else if coordinator.hoveredRowID == item.id { coordinator.hoveredRowID = nil }
        }
    }
}
