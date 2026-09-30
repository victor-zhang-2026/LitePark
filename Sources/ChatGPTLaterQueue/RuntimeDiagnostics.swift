import AppKit
import ApplicationServices

enum RuntimeDiagnostics {
    @MainActor static func testReopen() async {
        let items = LaterStore().items
        let initial = try? ChatGPTAX.captureTitle()
        print("trusted=\(ChatGPTAX.trusted()) saved=\(items.count)")
        var failures = 0
        for round in 0..<2 {
            for (index, item) in items.enumerated() {
                let before = try? ChatGPTAX.captureTitle()
                let start = Date()
                do {
                    try await ChatGPTAX.reopen(title: item.title)
                    let passed = (try? ChatGPTAX.captureTitle()) == item.title
                    print("\(passed ? "PASS" : "FAIL") reopen round=\(round) savedIndex=\(index) changed=\(before != item.title) seconds=\(Date().timeIntervalSince(start))")
                    if !passed { failures += 1 }
                } catch {
                    print("FAIL reopen savedIndex=\(index) error=\(error.localizedDescription)")
                    failures += 1
                }
            }
        }
        let before = try? ChatGPTAX.captureTitle()
        do {
            try await ChatGPTAX.reopen(title: "LaterQueueMissing-" + UUID().uuidString)
            print("FAIL missing title unexpectedly opened"); failures += 1
        } catch LaterError.sidebarUnavailable {
            let unchanged = (try? ChatGPTAX.captureTitle()) == before
            print("\(unchanged ? "PASS" : "FAIL") missing title no navigation")
            if !unchanged { failures += 1 }
        } catch { print("FAIL missing title error=\(error)"); failures += 1 }
        if let initial { try? await ChatGPTAX.reopen(title: initial) }
        print("REOPEN_FAILURES=\(failures)")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    /// Exercise the real production path from distinct macOS background states.
    /// Only navigation metadata is logged; the user's queue is never modified.
    @MainActor static func testBackgroundReopen() async {
        guard let app = try? ChatGPTAX.application(), ChatGPTAX.trusted() else {
            print("FAIL app or permission unavailable"); fflush(stdout); exit(1)
        }
        let items = LaterStore().items
        guard !items.isEmpty else { print("FAIL no saved test targets"); fflush(stdout); exit(1) }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let initial = try? ChatGPTAX.captureTitle()
        var failures = 0
        let utility = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 90),
                               styleMask: [.titled], backing: .buffered, defer: false)
        utility.title = "Background reopen verification"
        utility.isReleasedWhenClosed = false
        utility.center()
        for mode in ["current-background", "hidden", "behind-utility", "minimized", "closed-window"] {
            let targets = ["current-background", "closed-window"].contains(mode) ? Array(items.prefix(1)) : items
            for (index, item) in targets.enumerated() {
                do {
                    if mode == "hidden" {
                        app.hide()
                        guard await ChatGPTAX.waitUntil(2, { app.isHidden }) else { throw LaterError.verificationFailed }
                    } else if mode == "behind-utility" {
                        utility.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                        guard await ChatGPTAX.waitUntil(2, { !app.isActive }) else { throw LaterError.verificationFailed }
                    } else if mode == "closed-window" {
                        let window = try await ChatGPTAX.readyWindow(app, root: root)
                        guard let close = ChatGPTAX.copy(window, kAXCloseButtonAttribute),
                              AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString) == .success,
                              await ChatGPTAX.waitUntil(2, { (ChatGPTAX.copy(root, kAXWindowsAttribute) as? [AXUIElement] ?? []).isEmpty }) else { throw LaterError.verificationFailed }
                    } else if mode == "minimized" {
                        let window = try await ChatGPTAX.readyWindow(app, root: root)
                        guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success,
                              await ChatGPTAX.waitUntil(2, { ChatGPTAX.copy(window, kAXMinimizedAttribute) as? Bool == true }) else { throw LaterError.verificationFailed }
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    let before = try? ChatGPTAX.captureTitle()
                    print("START mode=\(mode) index=\(index) active=\(app.isActive) hidden=\(app.isHidden) windows=\((ChatGPTAX.copy(root, kAXWindowsAttribute) as? [AXUIElement] ?? []).count)")
                    let start = Date()
                    try await ChatGPTAX.reopen(title: item.title)
                    let passed = (try? ChatGPTAX.captureTitle()) == item.title && app.isActive
                    print("\(passed ? "PASS" : "FAIL") mode=\(mode) index=\(index) titleVerified=\(passed) changed=\(before != item.title) seconds=\(Date().timeIntervalSince(start))")
                    if !passed { failures += 1 }
                } catch {
                    print("FAIL mode=\(mode) index=\(index) error=\(error.localizedDescription)")
                    failures += 1
                }
                fflush(stdout)
            }
        }
        if let initial { try? await ChatGPTAX.reopen(title: initial) }
        utility.orderOut(nil)
        print("BACKGROUND_REOPEN_FAILURES=\(failures)")
        fflush(stdout); exit(failures == 0 ? 0 : 1)
    }

    static func inspect() {
        print("trusted=\(ChatGPTAX.trusted())")
        guard ChatGPTAX.trusted(), let app = try? ChatGPTAX.application() else { return }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 1)
        if CommandLine.arguments.contains("--press-saved-first") {
            app.activate(options: [.activateIgnoringOtherApps])
            let deadline = Date().addingTimeInterval(2)
            while !app.isActive && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        }
        let windows = ChatGPTAX.copy(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        for attribute in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            var settable: DarwinBoolean = false
            let status = AXUIElementIsAttributeSettable(root, attribute as CFString, &settable)
            print("root \(attribute) value=\(ChatGPTAX.copy(root, attribute) as? Bool as Any) settable=\(settable.boolValue) status=\(status.rawValue)")
        }
        let saved = LaterStore().items
        print("windows=\(windows.count) savedItems=\(saved.count) active=\(app.isActive)")
        for (index, window) in windows.enumerated() {
            // Only roles, navigation titles and counts; never dump chat contents.
            var queue = [window]
            var nodes: [AXUIElement] = []
            var areas: [AXUIElement] = []
            while !queue.isEmpty && nodes.count < 5000 {
                let node = queue.removeFirst()
                nodes.append(node)
                if ChatGPTAX.role(node) == "AXWebArea" { areas.append(node) }
                queue.append(contentsOf: ChatGPTAX.children(node))
            }
            print("window[\(index)] role=\(ChatGPTAX.role(window)) main=\(ChatGPTAX.copy(window, kAXMainAttribute) as? Bool ?? false) areas=\(areas.count) nodes=\(nodes.count)")
            if areas.isEmpty {
                for node in nodes {
                    print("native role=\(ChatGPTAX.role(node)) title=\(ChatGPTAX.string(node, kAXTitleAttribute) ?? "") description=\(ChatGPTAX.string(node, kAXDescriptionAttribute) ?? "") identifier=\(ChatGPTAX.string(node, kAXIdentifierAttribute) ?? "")")
                }
            }
            for area in areas {
                let title = ChatGPTAX.string(area, kAXTitleAttribute) ?? ""
                print("  currentSavedIndex=\(saved.firstIndex(where: {$0.title == title}) ?? -1) title=\(title)")
            }
            for (i, item) in saved.enumerated() {
                let matches = nodes.filter { ChatGPTAX.role($0) == kAXButtonRole && ChatGPTAX.textValues($0).contains(item.title) }
                print("  saved[\(i)] matches=\(matches.count)")
                for match in matches {
                    var actions: CFArray?
                    let status = AXUIElementCopyActionNames(match, &actions)
                    print("    enabled=\(ChatGPTAX.copy(match, kAXEnabledAttribute) as? Bool ?? false) actions=\(actions as? [String] ?? []) status=\(status.rawValue)")
                    print("    directTitle=\(ChatGPTAX.string(match,kAXTitleAttribute) == item.title) directValue=\(ChatGPTAX.string(match,kAXValueAttribute) == item.title) directDescription=\(ChatGPTAX.string(match,kAXDescriptionAttribute) == item.title)")
                    var parent: AXUIElement? = match
                    for depth in 0..<5 {
                        guard let p = parent else { break }
                        print("    ancestor[\(depth)] role=\(ChatGPTAX.role(p)) subrole=\(ChatGPTAX.string(p,kAXSubroleAttribute) ?? "") description=\(ChatGPTAX.string(p,kAXDescriptionAttribute) ?? "")")
                        parent = ChatGPTAX.copy(p,kAXParentAttribute).map { $0 as! AXUIElement }
                    }
                    if i == 0 && matches.count == 1 && CommandLine.arguments.contains("--press-saved-first") {
                        let pressed = AXUIElementPerformAction(match, kAXPressAction as CFString)
                        print("    pressResult=\(pressed.rawValue)")
                        RunLoop.current.run(until: Date().addingTimeInterval(1))
                        print("    verified=\((try? ChatGPTAX.captureTitle()) == item.title)")
                        var names: CFArray?
                        AXUIElementCopyAttributeNames(match, &names)
                        print("    attributes=\(names as? [String] ?? [])")
                        let focused = AXUIElementSetAttributeValue(match,kAXFocusedAttribute as CFString,kCFBooleanTrue)
                        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                        print("    setFocus=\(focused.rawValue) focused=\(ChatGPTAX.copy(match,kAXFocusedAttribute) as? Bool ?? false)")
                        for attr in ["AXCustomActions", "AXDOMIdentifier", "AXDOMClassList", "AXSelected", "AXElementBusy", "AXFocusableAncestor"] {
                            print("    \(attr)=\(ChatGPTAX.copy(match,attr).map { String(describing:$0) } ?? "nil")")
                        }
                        for c in ChatGPTAX.children(match) {
                            var a: CFArray?
                            AXUIElementCopyActionNames(c,&a)
                            print("    child role=\(ChatGPTAX.role(c)) actions=\(a as? [String] ?? [])")
                        }
                        if focused == .success, ChatGPTAX.copy(match,kAXFocusedAttribute) as? Bool == true {
                            let source = CGEventSource(stateID: .hidSystemState)
                            CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)?.postToPid(app.processIdentifier)
                            CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)?.postToPid(app.processIdentifier)
                            RunLoop.current.run(until: Date().addingTimeInterval(1))
                            print("    keyboardVerified=\((try? ChatGPTAX.captureTitle()) == item.title)")
                        }
                    }
                }
            }
            print("roleCounts=\(Dictionary(grouping: nodes, by: {ChatGPTAX.role($0)}).mapValues {$0.count})")
            for node in nodes where ChatGPTAX.role(node) == kAXButtonRole {
                let label = ChatGPTAX.label(node)
                if ["Show sidebar", "Open sidebar", "Toggle sidebar", "展开边栏", "显示边栏"].contains(label) {
                    print("sidebarToggle=\(label)")
                }
            }
        }
    }
}
