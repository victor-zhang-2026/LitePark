import AppKit

/// Opt-in integration checks against real AppKit windows and run-loop animations.
/// Uses an empty temporary store and never touches the user's queue or ChatGPT.
enum PanelLifecycleTests {
    @MainActor static func run() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("items.json")
        let coordinator = QueueCoordinator(store: LaterStore(fileURL: url))
        let controller = FloatingPanelController(coordinator: coordinator, interactive: false, onSettings: {})
        func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        var failures = 0
        func check(_ name: String, open: Bool) {
            let s = controller.lifecycleSnapshot
            let passed = open ? s.shown && s.visible && s.alpha > 0.99 && s.expanded : !s.shown && !s.visible
            print("\(passed ? "PASS" : "FAIL") \(name) shown=\(s.shown) visible=\(s.visible) alpha=\(s.alpha) expanded=\(s.expanded)")
            if !passed { failures += 1 }
        }
        controller.triggerEntered()
        await pause(0.4)
        check("initial hover", open: true)
        controller.closePanel()
        await pause(0.04)
        controller.triggerEntered()
        await pause(0.6)
        check("reenter during closing animation", open: true)
        for cycle in 1...8 {
            controller.triggerExited()
            await pause(0.8)
            check("hover exit auto closes \(cycle)", open: false)
            controller.closePanel()
            await pause(0.4)
            check("explicit close \(cycle)", open: false)
            controller.triggerEntered()
            await pause(0.4)
            check("hover enter \(cycle)", open: true)
        }
        controller.triggerExited()
        await pause(0.15)
        controller.triggerEntered()
        await pause(0.7)
        check("return before hover timeout stays open", open: true)
        controller.openFromTriggerClick()
        controller.triggerExited()
        await pause(0.6)
        check("click stays open after pointer exits", open: true)
        controller.closePanel()
        await pause(0.4)
        check("explicit dismissal", open: false)
        for cycle in 1...12 {
            controller.openPanel()
            await pause(0.2)
            controller.closePanel()
            await pause(0.03)
            controller.openPanel()
            await pause(0.3)
            check("interrupted close \(cycle)", open: true)
        }
        coordinator.store.add(title: "Fixture")
        if let item = coordinator.store.items.first {
            coordinator.done(item)
            if coordinator.store.count != 0 {
                failures += 1; print("FAIL Done removal")
            } else { print("PASS Done removes item without feedback state") }
            coordinator.undo()
        }
        controller.closePanel()
        await pause(0.3)
        check("final dismissal", open: false)
        print("PANEL_TEST_FAILURES=\(failures)")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }
}
