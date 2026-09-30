import AppKit
import SwiftUI

struct QueueRowFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct QueueView: View {
    @ObservedObject var coordinator: QueueCoordinator
    @ObservedObject var store: LaterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(coordinator: QueueCoordinator) {
        self.coordinator = coordinator
        self.store = coordinator.store
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
                VStack(spacing: 0) {
                    ForEach(store.items) { item in
                        row(item)
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: QueueRowFrames.self,
                                    value: [item.id: proxy.frame(in: .named("laterQueue"))])
                            })
                            .overlay(alignment: .top) {
                                if coordinator.dropTargetID == item.id {
                                    Rectangle().fill(Color.laterAccent).frame(height: 2)
                                }
                            }
                    }
                    if coordinator.dropAtEnd {
                        Rectangle().fill(Color.laterAccent).frame(height: 2)
                    }
                }
            }
            .coordinateSpace(name: "laterQueue")
            .onPreferenceChange(QueueRowFrames.self) { coordinator.rowFrames = $0 }
            .frame(height: min(CGFloat(store.count) * 68 + 12, 420))
        }
    }

    private func row(_ item: LaterItem) -> some View {
        let hovered = coordinator.hoveredRowID == item.id && coordinator.draggingID == nil
        let dragging = coordinator.draggingID == item.id
        return HStack(spacing: 8) {
            Button { coordinator.done(item) } label: {
                Image(systemName: "circle").font(.system(size: 19)).foregroundStyle(Color.laterAccent)
                    .frame(width: 28, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Mark done")
            Button { coordinator.open(item) } label: {
                Text(item.title).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 48)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open \(item.title)")
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 32, height: 48).contentShape(Rectangle())
                .opacity((hovered || dragging) ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
                .help("Drag to reorder").accessibilityLabel("Drag to reorder")
                .highPriorityGesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .named("laterQueue"))
                        .onChanged {
                            NSCursor.closedHand.set()
                            coordinator.updateReorder(item.id, at: $0.location)
                        }
                        .onEnded {
                            coordinator.updateReorder(item.id, at: $0.location)
                            coordinator.finishReorder()
                            NSCursor.arrow.set()
                        }
                )
        }
        .padding(.horizontal, 8).frame(height: 68)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.laterAccent.opacity(dragging ? 0.12 : (hovered ? 0.09 : 0)))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: BrandArtwork.ink).opacity(hovered ? 0.075 : 0), lineWidth: 1)
                }
                .shadow(color: .black.opacity(hovered ? 0.12 : 0), radius: 3, x: 0, y: 1)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
                .allowsHitTesting(false)
        }
        .onHover { inside in
            if inside { coordinator.hoveredRowID = item.id }
            else if coordinator.hoveredRowID == item.id { coordinator.hoveredRowID = nil }
        }
    }
}
