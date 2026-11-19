import AppKit

enum ConversationSource: String, Codable {
    case chatGPT, doubao, workBuddy, qwenWork, doubaoWork

    var displayName: String {
        switch self {
        case .chatGPT: return "ChatGPT"
        case .doubao: return "Doubao"
        case .workBuddy: return "WorkBuddy"
        case .qwenWork: return "千问办公"
        case .doubaoWork: return "豆包工作"
        }
    }

    init?(app: NSRunningApplication) {
        switch app.bundleIdentifier {
        case ChatGPTAX.bundleID: self = .chatGPT
        case "com.bot.pc.doubao", "com.bot.pc.doubao.browser": self = .doubao
        case OfficeClient.buddy.bundle: self = .workBuddy
        case OfficeClient.qwen.bundle: self = .qwenWork
        case "com.work.pc.doubao", "com.work.pc.doubao.browser": self = .doubaoWork
        default: return nil
        }
    }

    @MainActor func capture(_ app: NSRunningApplication) async throws -> (title: String, target: String) {
        switch self {
        case .chatGPT:
            let title = try await ChatGPTAX.captureTitleForAdd()
            return (title, title)
        case .workBuddy: return try await OfficeClient.buddy.capture(app)
        case .qwenWork: return try await OfficeClient.qwen.capture(app)
        case .doubaoWork: return try await DoubaoCapture.capture(app, work: true)
        case .doubao: return try await DoubaoCapture.capture(app)
        }
    }

    @MainActor func reopen(_ target: String) async throws {
        switch self {
        case .chatGPT: try await ChatGPTAX.reopen(title: target)
        case .workBuddy: try await OfficeClient.buddy.reopen(target)
        case .qwenWork: try await OfficeClient.qwen.reopen(target)
        case .doubaoWork:
            guard let url = URL(string: target), DoubaoCapture.isClientConversation(url, work: true) else { throw DoubaoError.open }
            try await DoubaoCapture.reopenClientConversation(url, work: true)
        case .doubao:
            guard let route = URL(string: target),
                  DoubaoCapture.isClientConversation(route) || DoubaoCapture.officialURL(target) != nil else {
                throw DoubaoError.open
            }
            try await DoubaoCapture.reopenChatWindow(route)
        }
    }
}

enum DoubaoError: LocalizedError {
    case missing, link, open
    var errorDescription: String? {
        switch self {
        case .missing: return "No Doubao conversation detected."
        case .link: return "Couldn’t get the Doubao conversation link."
        case .open: return "Couldn’t open the Doubao conversation link."
        }
    }
}

enum DoubaoCapture {
    static func officialURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host?.lowercased(),
              host == "doubao.com" || host.hasSuffix(".doubao.com"), url.path.count > 1,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func isClientConversation(_ url: URL, work: Bool = false) -> Bool {
        url.scheme == "chrome" && url.host == (work ? "doubaowork-chat" : "doubao-chat") &&
            url.path.range(of: #"^/chat/[0-9]+/?$"#, options: .regularExpression) != nil
    }

    private static func address(_ node: AXUIElement) -> URL? {
        if let url = ChatGPTAX.copy(node, kAXURLAttribute) as? URL { return url }
        return ChatGPTAX.string(node, kAXValueAttribute).flatMap(URL.init(string:))
    }

    @MainActor static func reopenChatWindow(_ target: URL) async throws {
        // Capture accepts chat pages owned by either regular Doubao process.
        // Resolve the same owners here, filtering by the chat page before activation.
        let apps = ["com.bot.pc.doubao", "com.bot.pc.doubao.browser"].flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }
        typealias ChatWindow = (app: NSRunningApplication, root: AXUIElement, window: AXUIElement, area: AXUIElement)
        func visibleChatWindows() -> [ChatWindow] {
            var result: [ChatWindow] = []
            for app in apps {
                let root = AXUIElementCreateApplication(app.processIdentifier)
                var windows = ChatGPTAX.copy(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
                for key in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
                    if let value = ChatGPTAX.copy(root, key), CFGetTypeID(value) == AXUIElementGetTypeID() {
                        windows.insert(value as! AXUIElement, at: 0)
                    }
                }
                var seen = Set<AXUIElement>()
                for window in windows where seen.insert(window).inserted {
                    var pending = [window]
                    while let node = pending.popLast() {
                        if ChatGPTAX.role(node) != "AXWebArea" {
                            pending.append(contentsOf: ChatGPTAX.children(node))
                        } else if let page = address(node), page.scheme == "chrome", page.host == "doubao-chat",
                                  page.path == "/chat" || page.path.hasPrefix("/chat/") {
                            result.append((app, root, window, node))
                            break
                        }
                    }
                }
            }
            return result
        }
        var candidates = visibleChatWindows()
        if candidates.isEmpty, let client = apps.first(where: { $0.bundleIdentifier == "com.bot.pc.doubao" }) {
            // A background Doubao process can be running with its full-size window
            // offscreen. Reopen the main app as Finder would, without sending a URL.
            guard let location = client.bundleURL else { throw DoubaoError.open }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.createsNewApplicationInstance = false
            config.addsToRecentItems = false
            if client.isHidden { client.unhide() }
            _ = try await NSWorkspace.shared.openApplication(at: location, configuration: config)
            let root = AXUIElementCreateApplication(client.processIdentifier)
            let nativeWindows = ChatGPTAX.copy(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
            let chatWindows = nativeWindows.filter {
                ChatGPTAX.string($0, kAXSubroleAttribute) == kAXStandardWindowSubrole &&
                    ChatGPTAX.label($0) == "豆包"
            }
            if chatWindows.count == 1 {
                let window = chatWindows[0]
                if ChatGPTAX.copy(window, kAXMinimizedAttribute) as? Bool == true {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            }
            _ = await ChatGPTAX.waitUntil(4, {
                candidates = visibleChatWindows()
                return !candidates.isEmpty
            })
            RuntimeLog.write("doubao background restore: active=\(client.isActive) nativeWindows=\(nativeWindows.count) chatPages=\(candidates.count)")
        }
        for (app, root, window, node) in candidates {
            let current = address(node)
            func targetRow() -> AXUIElement? {
                ChatGPTAX.allNodes(node).first { ChatGPTAX.role($0) == "AXLink" && address($0) == target }
            }
            if current != target && targetRow() == nil {
                let reveal = ChatGPTAX.allNodes(node).filter {
                    ChatGPTAX.role($0) == "AXButton" &&
                        ["展开侧栏", "打开侧栏", "展开侧边栏", "打开侧边栏", "展开更多"].contains(ChatGPTAX.label($0))
                }
                for button in reveal {
                    guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { continue }
                    if await ChatGPTAX.waitUntil(0.8, { targetRow() != nil }) { break }
                }
                guard targetRow() != nil else { continue }
            }
            if ChatGPTAX.copy(window, kAXMinimizedAttribute) as? Bool == true {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            if !app.isActive { app.activate(options: [.activateIgnoringOtherApps]) }
            func focused() -> Bool {
                app.isActive && ChatGPTAX.copy(root, kAXFocusedWindowAttribute).map { CFEqual($0, window) } == true
            }
            guard await ChatGPTAX.waitUntil(1.5, focused) else { throw DoubaoError.open }
            if address(node) == target { return }
            guard let row = targetRow(), AXUIElementPerformAction(row, kAXPressAction as CFString) == .success else {
                throw DoubaoError.open
            }
            if await ChatGPTAX.waitUntil(3, {
                focused() && ChatGPTAX.allNodes(window).first(where: { ChatGPTAX.role($0) == "AXWebArea" }).flatMap(address) == target
            }) { return }
            throw DoubaoError.open
        }
        RuntimeLog.write("doubao: no matching row; inspected chat windows=\(candidates.count)")
        throw DoubaoError.open
    }

    @MainActor static func reopenClientConversation(_ target: URL, work: Bool = false) async throws {
        let bundle = work ? "com.work.pc.doubao" : "com.bot.pc.doubao"
        guard let location = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            throw DoubaoError.open
        }
        let app = try await NSWorkspace.shared.openApplication(at: location, configuration: .init())
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var pressed = false
        var expanded = false
        var lastPress = -20
        var dispatched = false
        var sawRow = false
        for attempt in 0..<50 {
            try await Task.sleep(nanoseconds: 120_000_000)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { continue }
            guard let window = ChatGPTAX.copy(root, kAXFocusedWindowAttribute),
                  CFGetTypeID(window) == AXUIElementGetTypeID() else { continue }
            let nodes = ChatGPTAX.allNodes(window as! AXUIElement)
            if nodes.contains(where: { ChatGPTAX.role($0) == "AXWebArea" && address($0) == target }) { return }
            let windows = ChatGPTAX.copy(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
            if let existing = windows.first(where: { candidate in
                !CFEqual(candidate, window) && ChatGPTAX.allNodes(candidate).contains {
                    ChatGPTAX.role($0) == "AXWebArea" && address($0) == target
                }
            }), AXUIElementPerformAction(existing, kAXRaiseAction as CFString) == .success {
                if attempt < 24 { continue }
            }
            if attempt >= 24 && !dispatched {
                // Target the owning client with the exact address captured from its page.
                dispatched = true
                _ = try? await NSWorkspace.shared.open([target], withApplicationAt: location, configuration: .init())
                continue
            }
            if attempt - lastPress >= 12 { pressed = false }
            if !pressed, let row = nodes.first(where: { ChatGPTAX.role($0) == "AXLink" && address($0) == target }) {
                sawRow = true
                lastPress = attempt
                pressed = AXUIElementPerformAction(row, kAXPressAction as CFString) == .success
            } else if !pressed && !expanded, let toggle = nodes.first(where: {
                ChatGPTAX.role($0) == "AXButton" && ["展开侧栏", "打开侧栏"].contains(ChatGPTAX.label($0))
            }) {
                expanded = AXUIElementPerformAction(toggle, kAXPressAction as CFString) == .success
            }
        }
        RuntimeLog.write("doubao reopen unverified: sidebarRow=\(sawRow) addressDispatched=\(dispatched)")
        throw DoubaoError.open
    }

    @MainActor static func capture(_ app: NSRunningApplication, work: Bool = false) async throws -> (String, String) {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard AXIsProcessTrusted() else { throw DoubaoError.link }
        let provider = work ? "豆包工作" : "豆包"
        let host = work ? "doubaowork-chat" : "doubao-chat"
        var stage = "focused-window"
        for _ in 0..<8 {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { throw DoubaoError.missing }
            if let focused = ChatGPTAX.copy(root, kAXFocusedWindowAttribute) ?? ChatGPTAX.copy(root, kAXMainWindowAttribute),
               CFGetTypeID(focused) == AXUIElementGetTypeID() {
                let window = focused as! AXUIElement
                var pending = [window]
                var results: [(String, String)] = []
                stage = "chat-page"
                while let node = pending.popLast() {
                    guard ChatGPTAX.role(node) == "AXWebArea" else {
                        pending.append(contentsOf: ChatGPTAX.children(node))
                        continue
                    }
                    guard let page = address(node), page.host == host else { continue }
                    stage = "conversation-address"
                    let suffix = " - " + provider
                    let heading = ChatGPTAX.label(node)
                    let title = heading.hasSuffix(suffix) ? String(heading.dropLast(suffix.count)) : nil
                    let rows = ChatGPTAX.allNodes(node).filter {
                        ChatGPTAX.role($0) == "AXLink" && address($0).map { isClientConversation($0, work: work) } == true
                    }
                    func rowName(_ row: AXUIElement) -> String? {
                        for key in [kAXDescriptionAttribute, kAXTitleAttribute] {
                            guard let raw = ChatGPTAX.string(row, key) else { continue }
                            let name = raw.replacingOccurrences(of: #"(?:^|\s+)(?:归档对话\s+)?更多\s*$"#, with: "", options: .regularExpression)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if !name.isEmpty && name != "归档对话" { return name }
                        }
                        return nil
                    }
                    if isClientConversation(page, work: work) {
                        let name = title ?? rows.first(where: { address($0) == page }).flatMap(rowName)
                        results.append((name ?? provider + "对话", page.absoluteString))
                    } else if page.path == "/chat", let title, !title.isEmpty {
                        let matches = rows.filter { rowName($0) == title }
                        if matches.count == 1, let link = address(matches[0]) {
                            results.append((title, link.absoluteString))
                        }
                    }
                }
                if results.count == 1, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                   let stillFocused = ChatGPTAX.copy(root, kAXFocusedWindowAttribute) ?? ChatGPTAX.copy(root, kAXMainWindowAttribute),
                   CFEqual(stillFocused, window) { return results[0] }
            }
            try await Task.sleep(nanoseconds: 120_000_000)
        }
        RuntimeLog.write("capture unavailable provider=\(provider) stage=\(stage)")
        throw DoubaoError.missing
    }
}
