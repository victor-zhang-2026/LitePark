import AppKit
import SQLite3

enum OfficeClient {
    case buddy, qwen

    var bundle: String {
        self == .buddy ? "com.tencent.workbuddy.mac" : "cn.qwenwork.desktop.mac"
    }

    private var missing: NSError {
        let name = self == .buddy ? "WorkBuddy" : "千问办公"
        return NSError(domain: "LitePark", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Couldn’t locate the conversation in " + name + "."
        ])
    }

    private func window(_ app: NSRunningApplication) throws -> AXUIElement {
        guard app.isActive else { throw missing }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        if ChatGPTAX.copy(root, "AXManualAccessibility") as? Bool != true {
            AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        guard let value = ChatGPTAX.copy(root, kAXFocusedWindowAttribute) ?? ChatGPTAX.copy(root, kAXMainWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { throw missing }
        return value as! AXUIElement
    }

    private func title(_ window: AXUIElement, _ nodes: [AXUIElement]) -> String? {
        switch self {
        case .qwen:
            let title = ChatGPTAX.label(window)
            return ["", "千问办公", "新任务", "任务"].contains(title) ? nil : title
        case .buddy:
            func heading(in root: AXUIElement) -> String? {
                for node in ChatGPTAX.allNodes(root, limit: 40) where ChatGPTAX.role(node) == "AXStaticText" {
                    let name = ChatGPTAX.string(node, kAXValueAttribute) ?? ChatGPTAX.label(node)
                    if !name.isEmpty && name != "WorkBuddy" { return name }
                }
                return nil
            }
            // The compact renderer flattens the title bar next to the navigation divider.
            for divider in nodes where ChatGPTAX.role(divider) == "AXSplitter" || ChatGPTAX.label(divider) == "调整导航宽度" {
                guard let parent = ChatGPTAX.copy(divider, kAXParentAttribute) else { continue }
                let peers = ChatGPTAX.children(parent as! AXUIElement)
                if let i = peers.firstIndex(of: divider), i+1 < peers.count,
                   let name = heading(in: peers[i+1]), buddySession(name) != nil { return name }
            }
            for search in nodes where [ChatGPTAX.label(search), ChatGPTAX.string(search, kAXHelpAttribute)].contains("对话内搜索") {
                var current = search
                for _ in 0..<3 {
                    guard let parent = ChatGPTAX.copy(current, kAXParentAttribute) else { break }
                    current = parent as! AXUIElement
                    if let name = heading(in: current), buddySession(name) != nil { return name }
                }
            }
            for node in nodes {
                let classes = ChatGPTAX.copy(node, "AXDOMClassList") as? [String] ?? []
                if classes.contains("workbuddy-topbar-title") || classes.contains("project-title"),
                   let name = heading(in: node) { return name }
            }
            return nil
        }
    }

    // Resolve only a visible title and its session ID. Do not read messages.
    private func buddySession(_ title: String) -> URL? {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".workbuddy/workbuddy.db")
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        let sql = "SELECT id FROM sessions WHERE deleted_at IS NULL AND coalesce(nullif(custom_title,''), title) = ? LIMIT 2"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, title, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW, let raw = sqlite3_column_text(stmt, 0) else { return nil }
        let id = String(cString: raw)
        guard UUID(uuidString: id) != nil, sqlite3_step(stmt) == SQLITE_DONE else { return nil }
        return URL(string: "workbuddy://chat/" + id)
    }

    private func rows(_ nodes: [AXUIElement], title: String) -> [AXUIElement] {
        switch self {
        case .qwen:
            guard let list = nodes.first(where: { ChatGPTAX.label($0) == "会话任务列表" }) else { return [] }
            return ChatGPTAX.allNodes(list).filter { node in
                ChatGPTAX.role(node) != "AXStaticText" && ChatGPTAX.children(node).contains {
                    ChatGPTAX.role($0) == "AXStaticText" && (ChatGPTAX.string($0, kAXValueAttribute) == title || ChatGPTAX.label($0) == title)
                }
            }
        case .buddy:
            guard let tabs = nodes.first(where: { ChatGPTAX.label($0) == "Agents tabs" }),
                  let sidebar = ChatGPTAX.copy(tabs, kAXParentAttribute) else { return [] }
            return ChatGPTAX.allNodes(sidebar as! AXUIElement).filter { node in
                guard ChatGPTAX.role(node) == "AXButton" else { return false }
                let label = ChatGPTAX.label(node)
                if label == title { return true }
                guard label.hasPrefix(title + " ") else { return false }
                let age = String(label.dropFirst(title.count + 1))
                return age.range(of: #"^(刚刚|今天|昨天|前天|\d+\s*(秒|分钟|小时|天|周|个月|年)前|\d{1,4}[-/.月]\d{1,2}([-/.]\d{1,2}|日)?)$"#, options: .regularExpression) != nil
            }
        }
    }

    @MainActor func capture(_ app: NSRunningApplication) async throws -> (String, String) {
        for _ in 0..<8 {
            guard app.isActive else { throw missing }
            if let focused = try? window(app) {
                let nodes = ChatGPTAX.allNodes(focused)
                if let current = title(focused, nodes), !current.isEmpty,
                   rows(nodes, title: current).count <= 1, app.isActive {
                    if self == .buddy, let link = buddySession(current) { return (current, link.absoluteString) }
                    return (current, current)
                }
            }
            try await Task.sleep(nanoseconds: 120_000_000)
        }
        throw missing
    }

    @MainActor func reopen(_ target: String) async throws {
        guard let location = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { throw missing }
        if self == .buddy {
            let url = URL(string: target)
            let link = url?.scheme == "workbuddy" && url?.host == "chat" && UUID(uuidString: url?.lastPathComponent ?? "") != nil ? url : buddySession(target)
            if let link {
                _ = try await NSWorkspace.shared.open([link], withApplicationAt: location, configuration: .init())
                return
            }
        }
        let app = try await NSWorkspace.shared.openApplication(at: location, configuration: .init())
        var pressed = false
        var expanded = false
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 150_000_000)
            guard let focused = try? window(app) else { continue }
            let nodes = ChatGPTAX.allNodes(focused)
            let matches = rows(nodes, title: target)
            if matches.count > 1 { throw missing }
            if matches.count == 1 && title(focused, nodes) == target { return }
            guard !pressed else { continue }
            if let row = matches.first {
                pressed = AXUIElementPerformAction(row, kAXPressAction as CFString) == .success
            } else if !expanded, let toggle = nodes.first(where: {
                ChatGPTAX.role($0) == "AXButton" && ["展开侧边栏", "展开侧栏"].contains(ChatGPTAX.label($0))
            }) {
                expanded = AXUIElementPerformAction(toggle, kAXPressAction as CFString) == .success
            }
        }
        throw missing
    }
}
