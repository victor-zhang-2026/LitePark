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
        case "com.bot.pc.doubao": self = .doubao
        case OfficeClient.buddy.bundle: self = .workBuddy
        case OfficeClient.qwen.bundle: self = .qwenWork
        case "com.work.pc.doubao": self = .doubaoWork
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
            if let route = URL(string: target), DoubaoCapture.isClientConversation(route) {
                try await DoubaoCapture.reopenClientConversation(route)
                return
            }
            guard let url = DoubaoCapture.officialURL(target), NSWorkspace.shared.open(url) else {
                throw DoubaoError.open
            }
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
        for attempt in 0..<(work ? 50 : 25) {
            try await Task.sleep(nanoseconds: 120_000_000)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { continue }
            guard let window = ChatGPTAX.copy(root, kAXFocusedWindowAttribute),
                  CFGetTypeID(window) == AXUIElementGetTypeID() else { continue }
            let nodes = ChatGPTAX.allNodes(window as! AXUIElement)
            if nodes.contains(where: { ChatGPTAX.role($0) == "AXWebArea" && address($0) == target }) { return }
            if work {
                // Reopening the app may focus a different chat window.
                let windows = ChatGPTAX.copy(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
                for candidate in windows where !CFEqual(candidate, window) {
                    if ChatGPTAX.allNodes(candidate).contains(where: { ChatGPTAX.role($0) == "AXWebArea" && address($0) == target }) {
                        AXUIElementPerformAction(candidate, kAXRaiseAction as CFString)
                        break
                    }
                }
                if attempt == 24 {
                    // Address comes verbatim from the work client. Dispatch it only
                    // to that application and continue verifying the focused page.
                    _ = try? await NSWorkspace.shared.open([target], withApplicationAt: location, configuration: .init())
                    continue
                }
                if attempt - lastPress >= 12 { pressed = false }
            }
            if !pressed, let row = nodes.first(where: { ChatGPTAX.role($0) == "AXLink" && address($0) == target }) {
                lastPress = attempt
                pressed = AXUIElementPerformAction(row, kAXPressAction as CFString) == .success
            } else if !pressed && !expanded, let toggle = nodes.first(where: {
                ChatGPTAX.role($0) == "AXButton" && ["展开侧栏", "打开侧栏"].contains(ChatGPTAX.label($0))
            }) {
                expanded = AXUIElementPerformAction(toggle, kAXPressAction as CFString) == .success
            }
        }
        throw DoubaoError.open
    }

    @MainActor static func capture(_ app: NSRunningApplication, work: Bool = false) async throws -> (String, String) {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard AXIsProcessTrusted() else { throw DoubaoError.link }
        guard let windowValue = ChatGPTAX.copy(root, kAXFocusedWindowAttribute),
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { throw DoubaoError.missing }
        let window = windowValue as! AXUIElement
        let nodes = ChatGPTAX.allNodes(window)
        func url(_ node: AXUIElement) -> URL? {
            ChatGPTAX.copy(node, kAXURLAttribute) as? URL
        }
        guard let area = nodes.first(where: { ChatGPTAX.role($0) == "AXWebArea" }),
              let current = url(area), isClientConversation(current, work: work) else {
            throw DoubaoError.missing
        }
        func active() -> Bool {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier && url(area) == current
        }
        let row = nodes.first { ChatGPTAX.role($0) == "AXLink" && address($0) == current }
        let title = row.map(ChatGPTAX.label)?.replacingOccurrences(of: " 归档对话 更多", with: "")
        if work {
            let pageTitle = ChatGPTAX.string(area, kAXTitleAttribute) ?? ""
            let suffix = " - 豆包工作"
            if pageTitle.hasSuffix(suffix), active() {
                let name = String(pageTitle.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { return (name, current.absoluteString) }
            }
            guard let row, active() else { throw DoubaoError.missing }
            // Chromium can expose action names in AXTitle and the conversation
            // name in AXDescription or as a nested static text element.
            let textNodes = ChatGPTAX.allNodes(row, limit: 40).filter { ChatGPTAX.role($0) == "AXStaticText" }
            let names = [ChatGPTAX.string(row, kAXDescriptionAttribute), ChatGPTAX.string(row, kAXTitleAttribute)]
                + textNodes.map { ChatGPTAX.string($0, kAXValueAttribute) }
            for name in names.compactMap({ $0 }) {
                let cleaned = name.replacingOccurrences(of: #"(?:^|\s+)(?:归档对话\s+)?更多\s*$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && !["归档对话", "更多"].contains(cleaned) {
                    return (cleaned, current.absoluteString)
                }
            }
            throw DoubaoError.missing
        }
        // The client exposes the same conversation address on the active page
        // and its sidebar link. Retain that exact address for native AX navigation.
        if row != nil && active() {
            return (title?.isEmpty == false ? title! : "Doubao conversation", current.absoluteString)
        }
        let board = NSPasteboard.general
        func press(_ node: AXUIElement) throws {
            guard active(), AXUIElementPerformAction(node, kAXPressAction as CFString) == .success else {
                throw DoubaoError.link
            }
        }
        guard let sidebar = nodes.first(where: { ["收起侧栏", "展开侧栏"].contains(ChatGPTAX.label($0)) }),
              let parent = ChatGPTAX.copy(sidebar, kAXParentAttribute),
              let more = ChatGPTAX.children(parent as! AXUIElement).first(where: { ChatGPTAX.label($0) == "更多" }) else {
            throw DoubaoError.link
        }
        let originalControls = Set(nodes)
        try press(more)
        let copyNames = ["复制链接", "复制对话链接", "Copy Link", "Copy conversation link"]
        var openedShare = false
        for _ in 0..<12 {
            try await Task.sleep(nanoseconds: 100_000_000)
            guard active() else { throw DoubaoError.link }
            let controls = ChatGPTAX.allNodes(root).filter {
                !originalControls.contains($0) && ["AXMenuItem", "AXButton", "AXLink"].contains(ChatGPTAX.role($0))
            }
            if let copy = controls.first(where: { copyNames.contains(ChatGPTAX.label($0)) }) {
                let revision = board.changeCount
                let saved = (board.pasteboardItems ?? []).map { item in
                    let clone = NSPasteboardItem()
                    for type in item.types {
                        if let data = item.data(forType: type) { clone.setData(data, forType: type) }
                    }
                    return clone
                }
                try press(copy)
                for _ in 0..<25 {
                    try await Task.sleep(nanoseconds: 80_000_000)
                    guard board.changeCount != revision else { continue }
                    let changed = board.changeCount
                    guard let value = board.string(forType: .URL) ?? board.string(forType: .string),
                          let link = officialURL(value) else { throw DoubaoError.link }
                    if board.changeCount == changed {
                        board.clearContents()
                        if !saved.isEmpty { board.writeObjects(saved) }
                    }
                    guard active() else { throw DoubaoError.link }
                    return (title?.isEmpty == false ? title! : "Doubao conversation", link.absoluteString)
                }
                break
            }
            if !openedShare, let share = controls.first(where: { ["分享对话", "分享", "Share Conversation"].contains(ChatGPTAX.label($0)) }) {
                try press(share)
                openedShare = true
            }
        }
        throw DoubaoError.link
    }
}
