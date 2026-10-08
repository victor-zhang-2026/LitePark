import Foundation
import CoreGraphics

@main struct PlacementTests {
    static func main() {
        let ball = CGSize(width: 48, height: 48)
        let screen = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let visible = CGRect(x: 0, y: 0, width: 1235, height: 690)
        let cases: [(String, CGPoint, CGPoint)] = [
            ("right Dock returns ball", CGPoint(x: 1224, y: 413), CGPoint(x: 1179, y: 413)),
            ("right overshoot clamps", CGPoint(x: 1300, y: 413), CGPoint(x: 1179, y: 413)),
            ("free movement within visible area", CGPoint(x: 1100, y: 413), CGPoint(x: 1100, y: 413)),
            ("left edge", CGPoint(x: -20, y: 413), CGPoint(x: 8, y: 413)),
            ("top menu bar edge", CGPoint(x: 600, y: 720), CGPoint(x: 600, y: 634)),
            ("bottom edge", CGPoint(x: 600, y: -20), CGPoint(x: 600, y: 8))
        ]
        for (name, origin, expected) in cases {
            let actual = TriggerPlacement.clamp(origin, size: ball, visibleFrame: visible)
            precondition(actual == expected, "FAIL \(name): \(actual)")
            precondition(TriggerPlacement.clamp(actual, size: ball, visibleFrame: visible) == expected, "restore drift")
            print("PASS \(name)")
        }
        let screens = [screen, CGRect(x: 1280, y: 0, width: 1440, height: 900), CGRect(x: -1200, y: 100, width: 1200, height: 800)]
        precondition(TriggerPlacement.screenIndex(mouse: CGPoint(x: 1600, y: 400), window: CGRect(x: 1580, y: 380, width: 48, height: 48), screens: screens) == 1)
        print("PASS pointer chooses connected display")
        precondition(TriggerPlacement.screenIndex(mouse: CGPoint(x: 1285, y: 400), window: CGRect(x: 1260, y: 390, width: 48, height: 48), screens: screens) == 1)
        print("PASS window straddling display boundary")
        precondition(TriggerPlacement.screenIndex(mouse: CGPoint(x: -500, y: 500), window: CGRect(x: -520, y: 480, width: 48, height: 48), screens: screens) == 2)
        print("PASS display with negative origin")
        precondition(TriggerPlacement.bestScreenIndex(window: CGRect(x: 1600, y: 400, width: 48, height: 48), screens: screens) == 1)
        print("PASS saved position chooses its display independently of pointer")
    }
}
