import Foundation
import CoreGraphics

@main struct PlacementTests {
    static func main() {
        let ball = CGSize(width: 48, height: 48)
        let screen = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let cases: [(String, CGPoint, CGRect, CGPoint)] = [
            ("right Dock does not reserve 45pt", CGPoint(x: 1224, y: 413), screen, CGPoint(x: 1224, y: 413)),
            ("right edge stays reachable", CGPoint(x: 1300, y: 413), screen, CGPoint(x: 1224, y: 413)),
            ("interior has no snapping", CGPoint(x: 1200, y: 413), screen, CGPoint(x: 1200, y: 413)),
            ("left edge", CGPoint(x: -20, y: 413), screen, CGPoint(x: 8, y: 413)),
            ("top edge", CGPoint(x: 600, y: 720), screen, CGPoint(x: 600, y: 664)),
            ("bottom edge", CGPoint(x: 600, y: -20), screen, CGPoint(x: 600, y: 8)),
            ("external display right", CGPoint(x: 2400, y: 200), CGRect(x: 1280, y: 0, width: 1280, height: 720), CGPoint(x: 2400, y: 200)),
            ("external display negative origin", CGPoint(x: -100, y: 200), CGRect(x: -1280, y: 0, width: 1280, height: 720), CGPoint(x: -100, y: 200))
        ]
        for (name, origin, frame, expected) in cases {
            let actual = TriggerPlacement.clamp(origin, size: ball, screenFrame: frame)
            precondition(actual == expected, "FAIL \(name): \(actual)")
            precondition(TriggerPlacement.clamp(actual, size: ball, screenFrame: frame) == expected, "restore drift")
            print("PASS \(name)")
        }
    }
}
