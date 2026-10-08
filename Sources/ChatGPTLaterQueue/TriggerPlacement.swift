import Foundation
import CoreGraphics

enum TriggerPlacement {
    /// Keep the ball outside the Dock/menu bar, matching LiteTick's placement.
    static func clamp(_ origin: CGPoint, size: CGSize, visibleFrame: CGRect) -> CGPoint {
        let inset: CGFloat = 8
        let minX = visibleFrame.minX + inset
        let minY = visibleFrame.minY + inset
        return CGPoint(
            x: min(max(origin.x, minX), max(minX, visibleFrame.maxX - size.width - inset)),
            y: min(max(origin.y, minY), max(minY, visibleFrame.maxY - size.height - inset))
        )
    }

    /// Prefer the display under the pointer; during a screen crossing the
    /// floating window may straddle displays, so use intersection as fallback.
    static func screenIndex(mouse: CGPoint, window: CGRect, screens: [CGRect]) -> Int? {
        if let index = screens.firstIndex(where: { $0.contains(mouse) }) { return index }
        return bestScreenIndex(window: window, screens: screens)
    }

    static func bestScreenIndex(window: CGRect, screens: [CGRect]) -> Int? {
        let areas = screens.map { screen -> CGFloat in
            let overlap = screen.intersection(window)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        if let index = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[index] > 0 { return index }
        guard !screens.isEmpty else { return nil }
        let point = CGPoint(x: window.midX, y: window.midY)
        return screens.indices.min { lhs, rhs in
            func distance(_ rect: CGRect) -> CGFloat {
                let x = min(max(point.x, rect.minX), rect.maxX)
                let y = min(max(point.y, rect.minY), rect.maxY)
                return hypot(point.x - x, point.y - y)
            }
            return distance(screens[lhs]) < distance(screens[rhs])
        }
    }
}
