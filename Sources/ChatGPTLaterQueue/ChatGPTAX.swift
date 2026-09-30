import AppKit
import ApplicationServices

enum RuntimeLog {
    static let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/ChatGPTLaterQueue/runtime.log")
    static func write(_ message: String) {
        let data = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n".data(using: .utf8)!
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        // Bounded, metadata-only local diagnostics. No titles or chat content.
        if (try? handle.seekToEnd()) ?? 0 > 256_000 { try? handle.truncate(atOffset: 0) }
        try? handle.write(contentsOf: data)
    }
}

enum ChatGPTAX {
    static let bundleID = "com.openai.codex"
    static func trusted() -> Bool { AXIsProcessTrusted() }
    static func requestTrustPrompt() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    static func application() throws -> NSRunningApplication {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else { throw LaterError.chatGPTNotRunning }
        return app
    }
    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
    static func string(_ element: AXUIElement, _ attribute: String) -> String? { copy(element, attribute) as? String }
    static func role(_ element: AXUIElement) -> String { string(element, kAXRoleAttribute) ?? "" }
    static func label(_ element: AXUIElement) -> String {
        let title = string(element, kAXTitleAttribute) ?? ""
        return title.isEmpty ? (string(element, kAXDescriptionAttribute) ?? "") : title
    }
    static func children(_ element: AXUIElement) -> [AXUIElement] { copy(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    static func allNodes(_ root: AXUIElement, limit: Int = 5000) -> [AXUIElement] {
        var result: [AXUIElement] = [], queue = [root], index = 0
        while index < queue.count && result.count < limit {
            let node = queue[index]; index += 1
            result.append(node); queue.append(contentsOf: children(node))
        }
        return result
    }
    static func normalized(_ text: String) -> String { text.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func textValues(_ element: AXUIElement, limit: Int = 40) -> [String] {
        allNodes(element, limit: limit).flatMap { node in
            [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].compactMap { string(node, $0) }
        }
    }
    static func root() throws -> (NSRunningApplication, AXUIElement) {
        guard trusted() else { requestTrustPrompt(); throw LaterError.accessibilityRequired }
        let app = try application()
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 1)
        // ChatGPT can suspend its detailed accessibility tree. Request the
        // richer UI only through the attribute the installed app exposes.
        let enhanced = "AXEnhancedUserInterface" as CFString
        if copy(root, enhanced as String) as? Bool == false {
            var settable: DarwinBoolean = false
            if AXUIElementIsAttributeSettable(root, enhanced, &settable) == .success, settable.boolValue {
                let status = AXUIElementSetAttributeValue(root, enhanced, kCFBooleanTrue)
                RuntimeLog.write("accessibility detailed tree requested status=\(status.rawValue)")
            }
        }
        return (app, root)
    }
    static func mainWindow(_ root: AXUIElement) throws -> AXUIElement {
        // Activation and AX window publication are separate asynchronous steps.
        // A focused utility window is not necessarily the conversation window.
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let value = copy(root, attribute) {
                let window = value as! AXUIElement
                if (try? currentTitle(window)) != nil { return window }
            }
        }
        let windows = copy(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let conversations = windows.filter { (try? currentTitle($0)) != nil }
        if let main = conversations.first(where: { copy($0, kAXMainAttribute) as? Bool == true }) { return main }
        guard conversations.count == 1 else { throw LaterError.noConversation }
        return conversations[0]
    }

    @MainActor static func readyWindow(_ app: NSRunningApplication, root: AXUIElement) async throws -> AXUIElement {
        RuntimeLog.write("reopen activation start hidden=\(app.isHidden) active=\(app.isActive) windows=\((copy(root, kAXWindowsAttribute) as? [AXUIElement] ?? []).count)")
        app.unhide()
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        var ready: AXUIElement?
        let resolve = {
            guard app.isActive, let window = try? mainWindow(root) else { return false }
            if copy(window, kAXMinimizedAttribute) as? Bool == true {
                _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                return false
            }
            ready = window
            return true
        }
        if !(await waitUntil(1.5, resolve)) {
            // A running app may have no exposed window (hidden/closed window or
            // a different Space). Normal LaunchServices reopening mirrors a
            // Dock/app launch and lets ChatGPT restore its own main window.
            guard let url = app.bundleURL else { throw LaterError.noConversation }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.addsToRecentItems = false
            RuntimeLog.write("reopen requesting LaunchServices window restore")
            let opened: Bool = await withCheckedContinuation { continuation in
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                    continuation.resume(returning: error == nil)
                }
            }
            guard opened, await waitUntil(4, resolve) else {
                RuntimeLog.write("reopen window_not_ready active=\(app.isActive) windows=\((copy(root, kAXWindowsAttribute) as? [AXUIElement] ?? []).count)")
                throw LaterError.noConversation
            }
        }
        guard let window = ready else { throw LaterError.noConversation }
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        RuntimeLog.write("reopen conversation_window_ready")
        return window
    }
    static func currentTitle(_ window: AXUIElement) throws -> String {
        // Stop at AXWebArea: capturing a title never traverses conversation text.
        var queue = [window], areas: [AXUIElement] = [], i = 0
        while i < queue.count && i < 200 {
            let node = queue[i]; i += 1
            if role(node) == "AXWebArea" { areas.append(node) }
            else { queue.append(contentsOf: children(node)) }
        }
        guard areas.count == 1, let title = string(areas[0], kAXTitleAttribute), !normalized(title).isEmpty else { throw LaterError.noConversation }
        return normalized(title)
    }
    static func captureTitle() throws -> String {
        let (_, root) = try root()
        return try currentTitle(mainWindow(root))
    }

    @MainActor static func captureTitleForAdd() async throws -> String {
        let (app, root) = try root()
        // Preserve the fast, passive read when the conversation is exposed.
        if let window = try? mainWindow(root), let title = try? currentTitle(window) {
            RuntimeLog.write("capture ready without window restoration")
            return title
        }
        RuntimeLog.write("capture waiting for conversation window")
        _ = try await readyWindow(app, root: root)
        var lastTitle: String?
        var stableSamples = 0
        let readable = await waitUntil(2, {
            guard let title = try? currentTitle(mainWindow(root)) else {
                lastTitle = nil; stableSamples = 0; return false
            }
            stableSamples = title == lastTitle ? stableSamples + 1 : 1
            lastTitle = title
            return stableSamples >= 3
        })
        guard readable, let title = lastTitle else { throw LaterError.noConversation }
        RuntimeLog.write("capture restored window and verified stable title")
        return title
    }

    static func sidebarButtons(_ window: AXUIElement, title: String) -> [AXUIElement] {
        let expected = normalized(title)
        return allNodes(window).filter { node in
            guard role(node) == kAXButtonRole else { return false }
            // Match the observed ChatGPT sidebar row, excluding the same title
            // in the conversation header and buttons inside message content.
            let classes = copy(node, "AXDOMClassList") as? [String] ?? []
            var isSidebar = classes.contains("sidebar-item")
            var ancestor = copy(node, kAXParentAttribute)
            for _ in 0..<8 {
                guard let value = ancestor else { break }
                let parent = value as! AXUIElement
                let description = string(parent, kAXDescriptionAttribute) ?? ""
                if role(parent) == kAXListRole && (description == "Chats" || description.hasPrefix("Chats in ")) { isSidebar = true; break }
                if string(parent, kAXSubroleAttribute) == "AXLandmarkMain" { return false }
                ancestor = copy(parent, kAXParentAttribute)
            }
            return isSidebar && textValues(node).contains(where: { normalized($0) == expected })
        }
    }

    @MainActor static func waitUntil(_ seconds: TimeInterval, _ predicate: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 60_000_000)
        } while Date() < deadline
        return predicate()
    }

    @MainActor static func reopen(title: String) async throws {
        let (app, root) = try root()
        let window = try await readyWindow(app, root: root)
        let expected = normalized(title)
        let matches = sidebarButtons(window, title: expected)
        RuntimeLog.write("reopen trusted=true sidebarMatches=\(matches.count)")
        guard !matches.isEmpty else { throw LaterError.sidebarUnavailable }
        guard matches.count == 1 else { throw LaterError.sidebarAmbiguous }
        let target = matches[0]
        let verify = { (try? currentTitle(mainWindow(root))) == expected && app.isActive }
        if verify() { return }
        var actions: CFArray?
        AXUIElementCopyActionNames(target, &actions)
        if (actions as? [String] ?? []).contains(kAXPressAction) {
            let result = AXUIElementPerformAction(target, kAXPressAction as CFString)
            RuntimeLog.write("reopen AXPress=\(result.rawValue)")
            if await waitUntil(0.8, verify) { return }
        }

        // This ChatGPT build does not advertise AXPress for sidebar rows.
        // Resolve a fresh exact row, confirm stable keyboard focus, then Return.
        // AX references can be replaced when the web UI finishes navigation.
        for attempt in 0..<2 {
            guard app.isActive else { throw LaterError.verificationFailed }
            let fresh = sidebarButtons(try mainWindow(root), title: expected)
            guard !fresh.isEmpty else { throw LaterError.sidebarUnavailable }
            guard fresh.count == 1 else { throw LaterError.sidebarAmbiguous }
            let row = fresh[0]
            let focused = AXUIElementSetAttributeValue(row, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            var stableSamples = 0
            let confirmed = await waitUntil(2, {
                let exactFocus = copy(root, kAXFocusedUIElementAttribute).map { CFEqual($0, row) } ?? false
                let correct = focused == .success && app.isActive && exactFocus && copy(row, kAXFocusedAttribute) as? Bool == true
                stableSamples = correct ? stableSamples + 1 : 0
                return stableSamples >= 3
            })
            RuntimeLog.write("reopen focus attempt=\(attempt) status=\(focused.rawValue) active=\(app.isActive) confirmed=\(confirmed)")
            guard confirmed else { continue }
            let source = CGEventSource(stateID: .hidSystemState)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) else { throw LaterError.verificationFailed }
            down.flags = []; up.flags = []
            down.postToPid(app.processIdentifier)
            try? await Task.sleep(nanoseconds: 30_000_000)
            up.postToPid(app.processIdentifier)
            let verified = await waitUntil(3, verify)
            RuntimeLog.write("reopen focusedReturn verified=\(verified) active=\(app.isActive)")
            if verified { return }
        }
        throw LaterError.verificationFailed
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!)
    }
}
