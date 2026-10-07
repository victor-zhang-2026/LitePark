import Foundation
import CoreGraphics

enum TriggerPlacement {
    /// Keep the ball reachable, without reserving Dock space at any edge.
    static func clamp(_ origin: CGPoint, size: CGSize, screenFrame: CGRect) -> CGPoint {
        let inset: CGFloat = 8
        let minX = screenFrame.minX + inset
        let minY = screenFrame.minY + inset
        return CGPoint(
            x: min(max(origin.x, minX), max(minX, screenFrame.maxX - size.width - inset)),
            y: min(max(origin.y, minY), max(minY, screenFrame.maxY - size.height - inset))
        )
    }
}
