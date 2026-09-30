import AppKit
import SwiftUI
import Combine
import ApplicationServices
import ServiceManagement
import Carbon.HIToolbox
import UniformTypeIdentifiers

// V1 retains its dark surfaces with one restrained warm-orange accent.
extension Color {
    static let laterAccent = Color(nsColor: BrandArtwork.primary)
    static let laterSurface = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    static let laterElevated = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
    static let laterSeparator = Color.white.opacity(0.14)
}

struct LaterItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var addedAt: Date
    var order: Int
}

enum LaterError: LocalizedError {
    case chatGPTNotRunning
    case accessibilityRequired
    case noConversation
    case sidebarUnavailable
    case sidebarAmbiguous
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .chatGPTNotRunning: return "ChatGPT isn’t running."
        case .accessibilityRequired: return "Accessibility access is required to identify and reopen ChatGPT conversations."
        case .noConversation: return "No ChatGPT conversation detected."
        case .sidebarUnavailable: return "Chat isn’t available in the current sidebar."
        case .sidebarAmbiguous: return "Multiple chats have this title."
        case .verificationFailed: return "Couldn’t verify the opened chat."
        }
    }
}

final class LaterStore: ObservableObject {
    @Published private(set) var items: [LaterItem] = []
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = base.appendingPathComponent("ChatGPTLaterQueue/items.json")
        }
        load()
    }

    var count: Int { items.count }

    func contains(title: String) -> Bool {
        items.contains { $0.title == title }
    }

    func add(title: String) {
        guard !contains(title: title) else { return }
        let item = LaterItem(id: UUID(), title: title, addedAt: Date(), order: 0)
        items.insert(item, at: 0)
        normalize()
        save()
    }

    func remove(at index: Int) -> LaterItem? {
        guard items.indices.contains(index) else { return nil }
        let item = items.remove(at: index)
        normalize()
        save()
        return item
    }

    func restore(_ item: LaterItem, at index: Int) {
        items.insert(item, at: min(max(index, 0), items.count))
        normalize()
        save()
    }

    func move(from offsets: IndexSet, to destination: Int) {
        items.move(fromOffsets: offsets, toOffset: destination)
        normalize()
        save()
    }

    func move(itemID: UUID, to destination: Int) {
        guard let from = items.firstIndex(where: { $0.id == itemID }), items.indices.contains(from) else { return }
        let item = items.remove(at: from)
        let target = min(max(destination, 0), items.count)
        items.insert(item, at: target)
        normalize()
        save()
    }

    func move(_ id: UUID, before targetID: UUID?) {
        guard id != targetID, let source = items.firstIndex(where: { $0.id == id }),
              targetID == nil || items.contains(where: { $0.id == targetID }) else { return }
        var reordered = items
        let item = reordered.remove(at: source)
        let destination = targetID.flatMap { target in reordered.firstIndex(where: { $0.id == target }) } ?? reordered.count
        reordered.insert(item, at: destination)
        items = reordered.enumerated().map { index, value in
            var value = value
            value.order = index
            return value
        }
        save()
        RuntimeLog.write("reorder committed from=\(source) to=\(destination) count=\(items.count)")
    }

    private func normalize() {
        items = items.enumerated().map { index, item in
            var copy = item
            copy.order = index
            return copy
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            items = try JSONDecoder().decode([LaterItem].self, from: data).sorted { $0.order < $1.order }
            normalize()
        } catch {
            items = []
        }
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("LitePark persistence failed: %@", error.localizedDescription)
        }
    }
}

final class QueueCoordinator: ObservableObject {
    @Published var islandState: IslandState = .idle
    let store: LaterStore
    private var undoItem: (LaterItem, Int)?
    private var undoWork: DispatchWorkItem?
    @Published var hoveredRowID: UUID?
    @Published var draggingID: UUID?
    @Published var dropTargetID: UUID?
    @Published var dropAtEnd = false
    var rowFrames: [UUID: CGRect] = [:]
    private var storeSubscription: AnyCancellable?

    init(store: LaterStore = LaterStore()) {
        self.store = store
        storeSubscription = store.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    func updateReorder(_ id: UUID, at point: CGPoint) {
        draggingID = id
        let frames = rowFrames.filter { $0.key != id }.sorted { $0.value.midY < $1.value.midY }
        dropTargetID = frames.first(where: { point.y < $0.value.midY })?.key
        dropAtEnd = dropTargetID == nil
    }

    func finishReorder() {
        defer { draggingID = nil; dropTargetID = nil; dropAtEnd = false }
        guard let id = draggingID else { return }
        store.move(id, before: dropTargetID)
    }

    private var isCapturing = false

    func addCurrent() {
        guard !isCapturing else { return }
        isCapturing = true
        Task { @MainActor in
            defer { isCapturing = false }
            do {
                let title = try await ChatGPTAX.captureTitleForAdd()
                if store.contains(title: title) {
                    RuntimeLog.write("add duplicate ignored")
                } else {
                    store.add(title: title)
                    RuntimeLog.write("add saved")
                }
            } catch {
                RuntimeLog.write("add failed: \(error.localizedDescription)")
            }
        }
    }

    @Published var isOpening = false

    func open(_ item: LaterItem) {
        guard !isOpening else { return }
        isOpening = true
        RuntimeLog.write("open requested")
        Task { @MainActor in
            defer { isOpening = false }
            do {
                try await ChatGPTAX.reopen(title: item.title)
                islandState = .idle
                RuntimeLog.write("open OPENED_AND_VERIFIED")
            } catch {
                islandState = .expanded
                RuntimeLog.write("open failed: \(error.localizedDescription)")
            }
        }
    }

    func done(_ item: LaterItem) {
        guard let index = store.items.firstIndex(of: item) else { return }
        undoItem = (item, index)
        _ = store.remove(at: index)
        islandState = .expanded
        let work = DispatchWorkItem { [weak self] in
            self?.undoItem = nil
        }
        undoWork?.cancel()
        undoWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    func undo() {
        guard let undoItem else { return }
        store.restore(undoItem.0, at: undoItem.1)
        self.undoItem = nil
        undoWork?.cancel()
        islandState = .expanded
    }

    var canUndo: Bool { undoItem != nil }

    func toggle() { islandState = islandState == .expanded ? .idle : .expanded }
    func collapse() {
        islandState = .idle
    }
}

enum IslandState: Equatable { case idle, expanded }

final class GlobalShortcutMonitor {
    private var addRef: EventHotKeyRef?
    private var toggleRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastFire = Date.distantPast
    private let add: () -> Void
    private let toggle: () -> Void

    init(add: @escaping () -> Void, toggle: @escaping () -> Void) {
        self.add = add
        self.toggle = toggle
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let size = UInt32(MemoryLayout<EventHotKeyID>.size)
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, Int(size), nil, &hotKeyID)
            DispatchQueue.main.async {
                monitor.fire(hotKeyID.id)
            }
            return noErr
        }
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventSpec,
                            Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        let signature = OSType(0x4C515545) // LQUE
        let modifiers = UInt32(controlKey | optionKey)
        let addID = EventHotKeyID(signature: signature, id: 1)
        let toggleID = EventHotKeyID(signature: signature, id: 2)
        let addStatus = RegisterEventHotKey(UInt32(kVK_ANSI_L), modifiers, addID, GetApplicationEventTarget(), 0, &addRef)
        let toggleStatus = RegisterEventHotKey(UInt32(kVK_ANSI_K), modifiers, toggleID, GetApplicationEventTarget(), 0, &toggleRef)
        RuntimeLog.write("shortcut registration handler=\(handlerStatus) add=\(addStatus) toggle=\(toggleStatus)")
        if addStatus != noErr || toggleStatus != noErr {
            NSLog("[LitePark] shortcut unavailable (L=%d K=%d)", addStatus, toggleStatus)
        }

        let fallback: (NSEvent) -> Void = { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains([.control, .option]) else { return }
            if event.keyCode == UInt16(kVK_ANSI_L) { self?.fire(1) }
            if event.keyCode == UInt16(kVK_ANSI_K) { self?.fire(2) }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: fallback)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in fallback(event); return event }
    }

    private func fire(_ id: UInt32) {
        let now = Date()
        guard now.timeIntervalSince(lastFire) > 0.20 else { return }
        lastFire = now
        RuntimeLog.write("shortcut received id=\(id)")
        if id == 1 { add() }
        if id == 2 { toggle() }
    }

    deinit {
        if let addRef { UnregisterEventHotKey(addRef) }
        if let toggleRef { UnregisterEventHotKey(toggleRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}

struct NotchGeometry {
    let screen: NSScreen
    let notchRect: NSRect?

    static func current() -> NotchGeometry {
        let screen = screenContainingChatGPT() ?? NSScreen.main ?? NSScreen.screens.first!
        let frame = screen.frame
        var notch: NSRect?
        if #available(macOS 12.0, *) {
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                let gapStart = left.maxX
                let gapEnd = right.minX
                let width = gapEnd - gapStart
                let height = max(screen.safeAreaInsets.top, 0)
                if width > 20, height > 0 {
                    notch = NSRect(x: gapStart, y: frame.maxY - height, width: width, height: height)
                }
            }
        }
        return NotchGeometry(screen: screen, notchRect: notch)
    }

    private static func screenContainingChatGPT() -> NSScreen? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == ChatGPTAX.bundleID }) else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows = ChatGPTAX.copy(root, kAXWindowsAttribute) as? [AXUIElement], let window = windows.first else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard let positionRef = ChatGPTAX.copy(window, kAXPositionAttribute),
              let sizeRef = ChatGPTAX.copy(window, kAXSizeAttribute) else { return nil }
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        let center = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
    }

    var anchorX: CGFloat {
        notchRect?.midX ?? screen.frame.midX
    }

    var topY: CGFloat { screen.frame.maxY }

    var hasPhysicalNotch: Bool { notchRect != nil }
}

final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let coordinator: QueueCoordinator
    private let onSettings: () -> Void
    private let interactive: Bool
    private var triggerPanel: LaterFloatingPanel!
    private var panel: NSPanel!
    private var triggerView: FloatingTriggerView!
    private var cancellables = Set<AnyCancellable>()
    private var outsideMonitor: Any?
    private var localOutsideMonitor: Any?
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?
    private var closeWork: DispatchWorkItem?
    private var transitionID: UInt = 0
    private var isShown = false
    private var triggerHovered = false
    private var listHovered = false
    private var isPinned = false
    private var draggingTrigger = false
    private let triggerSize = NSSize(width: 48, height: 48)
    private let panelOriginXKey = "floatingPanelOriginX"
    private let panelOriginYKey = "floatingPanelOriginY"

    // Used by the local AppKit regression harness; no conversation data.
    var lifecycleSnapshot: (shown: Bool, visible: Bool, alpha: CGFloat, expanded: Bool) {
        (isShown, panel.isVisible, panel.alphaValue, coordinator.islandState == .expanded)
    }

    init(coordinator: QueueCoordinator, interactive: Bool = true, onSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onSettings = onSettings
        self.interactive = interactive
        super.init()
        configurePanels()
        // Published sends from willSet. Handle it after the value is committed,
        // without recursively writing presentation state from this subscriber.
        coordinator.$islandState.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] state in
            guard let self, self.coordinator.islandState == state else { return }
            switch state {
            case .idle: self.closePanel()
            case .expanded: self.presentPanel(animate: true, activate: true)
            }
        }.store(in: &cancellables)
        coordinator.store.$items.receive(on: DispatchQueue.main).sink { [weak self] items in
            self?.triggerView?.count = items.count
            self?.refreshPanel()
        }.store(in: &cancellables)
        NotificationCenter.default.addObserver(self, selector: #selector(displayParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if interactive { showTrigger() }
        else { triggerPanel.ignoresMouseEvents = true; panel.ignoresMouseEvents = true }
    }

    deinit {
        removeDismissMonitors()
        NotificationCenter.default.removeObserver(self)
    }

    func togglePanel() { isShown ? closePanel() : openFromTriggerClick() }

    func showTrigger() {
        triggerPanel.setFrameOrigin(savedTriggerOrigin())
        triggerPanel.orderFrontRegardless()
    }

    func openPanel(animate: Bool = true) {
        if coordinator.islandState != .expanded { coordinator.islandState = .expanded }
        presentPanel(animate: animate, activate: true)
    }

    private func presentPanel(animate: Bool, activate: Bool) {
        if isShown {
            refreshPanel()
            return
        }
        closeWork?.cancel()
        closeWork = nil
        transitionID &+= 1
        let openingID = transitionID
        isShown = true
        refreshPanel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        if activate && interactive {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
            panel.makeFirstResponder(nil)
        }
        // Install dismissal monitors after the opening mouse event has
        // completed. Installing them synchronously can classify the same
        // trigger click as an outside click on some AppKit/event-source paths.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShown, self.transitionID == openingID else { return }
            self.installDismissMonitors()
        }
        if animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 1
            }
        } else { panel.alphaValue = 1 }
    }

    func closePanel() {
        guard isShown else { return }
        isShown = false
        coordinator.hoveredRowID = nil
        isPinned = false
        listHovered = false
        transitionID &+= 1
        let closingID = transitionID
        removeDismissMonitors()
        closeWork?.cancel()
        closeWork = nil
        panel.makeFirstResponder(nil)
        if coordinator.islandState != .idle { coordinator.islandState = .idle }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            self.panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                // A prior close must never hide a newly opened window.
                guard let self, !self.isShown, self.transitionID == closingID else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        })
    }

    func listHoverChanged(_ hovering: Bool) {
        guard interactive else { return }
        listHovered = hovering
        if hovering { closeWork?.cancel() } else { scheduleHoverClose() }
    }

    func triggerEntered() {
        triggerHovered = true
        closeWork?.cancel()
        // Match LiteTick: entering the floating ball opens the list. The
        // dismissal monitors are installed on the next run-loop turn, so this
        // hover transition cannot be mistaken for an outside click.
        if !isShown { openPanel(animate: true) }
    }

    func triggerExited() {
        triggerHovered = false
        scheduleHoverClose()
    }

    private func scheduleHoverClose() {
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isShown, !self.isPinned,
                  !self.triggerHovered, !self.listHovered,
                  self.coordinator.draggingID == nil else { return }
            self.closePanel()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func openFromTriggerClick() {
        isPinned = true
        triggerHovered = true
        closeWork?.cancel()
        openPanel(animate: true)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func moveTrigger(by translation: CGSize, ended: Bool) {
        let current = triggerPanel.frame.origin
        let proposed = NSPoint(x: current.x + translation.width, y: current.y - translation.height)
        triggerPanel.setFrameOrigin(proposed)
        draggingTrigger = true
        if ended {
            let screen = screenContaining(NSRect(origin: proposed, size: triggerSize)) ?? NSScreen.main!
            let settled = constrainedTriggerOrigin(proposed, to: screen)
            triggerPanel.setFrameOrigin(settled)
            UserDefaults.standard.set(Double(settled.x), forKey: "triggerX")
            UserDefaults.standard.set(Double(settled.y), forKey: "triggerY")
            draggingTrigger = false
            if isShown { refreshPanel() }
        }
    }

    private func configurePanels() {
        triggerPanel = LaterFloatingPanel(contentRect: NSRect(origin: .zero, size: triggerSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        prepare(triggerPanel)
        triggerPanel.becomesKeyOnlyIfNeeded = true
        triggerPanel.hasShadow = false
        triggerView = FloatingTriggerView(controller: self)
        triggerView.frame = NSRect(origin: .zero, size: triggerSize)
        triggerView.autoresizingMask = [.width, .height]
        triggerView.layer?.backgroundColor = NSColor.clear.cgColor
        triggerView.layer?.isOpaque = false
        triggerView.count = coordinator.store.count
        triggerView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.22).cgColor
        triggerView.layer?.shadowOpacity = 1
        triggerView.layer?.shadowRadius = 5
        triggerView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        triggerPanel.contentView = triggerView

        panel = LaterFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 190), styleMask: [.borderless], backing: .buffered, defer: false)
        prepare(panel)
        // The SwiftUI surface owns the single restrained shadow. Keeping the
        // native NSPanel shadow off avoids the duplicate outer frame seen below
        // the queue on click-open.
        panel.hasShadow = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: FloatingPanelView(coordinator: coordinator, controller: self, onSettings: onSettings))
        panel.contentView?.autoresizingMask = [.width, .height]
    }

    private func prepare(_ window: NSPanel) {
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.animationBehavior = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
    }

    private func refreshPanel() {
        guard isShown else { return }
        let height: CGFloat = expandedHeight()
        let size = NSSize(width: 420, height: height)
        let visible = (screenContaining(triggerPanel.frame) ?? NSScreen.main!).visibleFrame
        let trigger = triggerPanel.frame
        let leftSpace = trigger.minX - visible.minX - 12
        let rightSpace = visible.maxX - trigger.maxX - 12
        let proposedX = leftSpace >= size.width || leftSpace >= rightSpace ? trigger.minX - size.width : trigger.maxX
        let x = min(max(proposedX, visible.minX + 12), visible.maxX - size.width - 12)
        let y = min(max(trigger.midY - size.height / 2, visible.minY + 12), visible.maxY - size.height - 12)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func expandedHeight() -> CGFloat {
        coordinator.store.count == 0 ? 190 : min(560, 62 + CGFloat(min(coordinator.store.count, 6)) * 68 + 18)
    }

    private func installDismissMonitors() {
        guard interactive, outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, self.coordinator.draggingID == nil else { return }
            let point = NSEvent.mouseLocation
            guard !self.panel.frame.contains(point), !self.triggerPanel.frame.contains(point) else { return }
            RuntimeLog.write("panel dismissed outside global")
            self.closePanel()
        }
        localOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.isShown else { return event }
            if event.window === self.panel {
                self.isPinned = true
                self.closeWork?.cancel()
            }
            if event.window !== self.panel && event.window !== self.triggerPanel && self.coordinator.draggingID == nil {
                RuntimeLog.write("panel dismissed outside local")
                self.closePanel()
            }
            return event
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in if event.keyCode == 53 { self?.closePanel() } }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.closePanel(); return nil
        }
    }

    private func removeDismissMonitors() {
        [outsideMonitor, localOutsideMonitor, keyMonitor, localKeyMonitor].compactMap { $0 }.forEach { NSEvent.removeMonitor($0) }
        outsideMonitor = nil; localOutsideMonitor = nil; keyMonitor = nil; localKeyMonitor = nil
    }

    @objc private func displayParametersChanged() { showTrigger(); if isShown { refreshPanel() } }

    private func screenContaining(_ frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    private func constrainedTriggerOrigin(_ origin: NSPoint, to screen: NSScreen) -> NSPoint {
        let frame = screen.visibleFrame
        return NSPoint(x: min(max(origin.x, frame.minX + 8), frame.maxX - triggerSize.width - 8), y: min(max(origin.y, frame.minY + 8), frame.maxY - triggerSize.height - 8))
    }

    private func savedTriggerOrigin() -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        if UserDefaults.standard.object(forKey: "triggerX") != nil {
            let origin = NSPoint(x: UserDefaults.standard.double(forKey: "triggerX"), y: UserDefaults.standard.double(forKey: "triggerY"))
            return constrainedTriggerOrigin(origin, to: screenContaining(NSRect(origin: origin, size: triggerSize)) ?? screen)
        }
        return NSPoint(x: screen.visibleFrame.maxX - triggerSize.width - 12, y: screen.visibleFrame.midY - triggerSize.height / 2)
    }

}

final class FloatingTriggerView: NSView {
    weak var controller: FloatingPanelController?
    var count = 0 { didSet { needsDisplay = true } }
    private var lastPoint: NSPoint?
    private var dragged = false
    private var trackingAreaRef: NSTrackingArea?
    private var hoverAmount: CGFloat = 0
    private var hoverTarget = false
    private var hoverTimer: Timer?

    deinit { hoverTimer?.invalidate() }

    private func setHovered(_ hovering: Bool) {
        guard hoverTarget != hovering else { return }
        hoverTarget = hovering
        hoverTimer?.invalidate()
        hoverTimer = nil
        let target: CGFloat = hovering ? 1 : 0
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            hoverAmount = target; needsDisplay = true; return
        }
        let startAmount = hoverAmount
        let startTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - startTime) / 0.16)
            let eased = 1 - pow(1 - progress, 3)
            self.hoverAmount = startAmount + (target - startAmount) * CGFloat(eased)
            self.needsDisplay = true
            if progress >= 1 { timer.invalidate(); self.hoverTimer = nil }
        }
        hoverTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    init(controller: FloatingPanelController) { self.controller = controller; super.init(frame: .zero); wantsLayer = true }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }
    override func draw(_ dirtyRect: NSRect) {
        let outer = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.20 + 0.10 * hoverAmount)
        shadow.shadowBlurRadius = 5 + 1.5 * hoverAmount
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        outer.fill()
        NSGraphicsContext.restoreGraphicsState()

        BrandArtwork.drawTrigger(in: bounds.insetBy(dx: 3, dy: 3), hover: hoverAmount)
        if count > 0 {
            let label = count > 99 ? "99+" : "\(count)"
            let badgeSize: CGFloat = label.count > 2 ? 23 : 17
            let badgeRect = NSRect(x: bounds.maxX - badgeSize - 1, y: bounds.maxY - badgeSize - 1, width: badgeSize, height: badgeSize)
            let badge = NSBezierPath(ovalIn: badgeRect)
            let badgeShadow = NSShadow()
            badgeShadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
            badgeShadow.shadowBlurRadius = 3
            badgeShadow.shadowOffset = NSSize(width: 0, height: -1)
            NSGraphicsContext.saveGraphicsState()
            badgeShadow.set()
            NSColor(calibratedRed: 1, green: 0.23, blue: 0.19, alpha: 1).setFill()
            badge.fill()
            NSGraphicsContext.restoreGraphicsState()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: label.count > 2 ? 8 : 10, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let textSize = (label as NSString).size(withAttributes: attributes)
            (label as NSString).draw(at: NSPoint(x: badgeRect.midX - textSize.width / 2, y: badgeRect.midY - textSize.height / 2 + 1), withAttributes: attributes)
        }
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true); controller?.triggerEntered() }
    override func mouseExited(with event: NSEvent) { setHovered(false); controller?.triggerExited() }
    override func mouseDown(with event: NSEvent) { lastPoint = NSEvent.mouseLocation; dragged = false }
    override func mouseDragged(with event: NSEvent) { guard let lastPoint else { return }; let current = NSEvent.mouseLocation; if hypot(current.x-lastPoint.x, current.y-lastPoint.y) > 1 { dragged = true }; controller?.moveTrigger(by: CGSize(width: current.x-lastPoint.x, height: lastPoint.y-current.y), ended: false); self.lastPoint = current }
    override func mouseUp(with event: NSEvent) {
        if dragged {
            controller?.moveTrigger(by: .zero, ended: true)
        } else {
            controller?.openFromTriggerClick()
        }
        lastPoint = nil
        dragged = false
    }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let quit = NSMenuItem(title: "Quit LitePark", action: #selector(quitApplication), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func quitApplication() { controller?.quit() }
}

final class LaterFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct FloatingPanelView: View {
    @ObservedObject var coordinator: QueueCoordinator
    let controller: FloatingPanelController
    let onSettings: () -> Void

    var body: some View {
        Group {
            switch coordinator.islandState {
            case .idle: expanded
            case .expanded: expanded
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { controller.listHoverChanged($0) }
        .preferredColorScheme(.dark)
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 11) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                    Text("LitePark")
                        .font(.system(size: 15, weight: .semibold))
                }
                Spacer()
                Text("\(coordinator.store.count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.70))
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.white.opacity(0.78))
                        .accessibilityLabel("Settings")
                }.buttonStyle(.plain)
                Button { coordinator.collapse() } label: {
                    Image(systemName: "xmark").foregroundStyle(.white.opacity(0.78))
                }.buttonStyle(.plain).accessibilityLabel("Close LitePark")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).frame(height: 54)
        .background(Color.laterElevated)
        QueueView(coordinator: coordinator)
        }
        .background(Color.laterSurface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.laterSeparator, lineWidth: 1)
        }
        .frame(width: 420, alignment: .top)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: QueueCoordinator!
    private var floatingPanel: FloatingPanelController!
    private var shortcuts: GlobalShortcutMonitor!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--test-background-reopen") {
            Task { @MainActor in await RuntimeDiagnostics.testBackgroundReopen() }
            return
        }
        if CommandLine.arguments.contains("--test-reopen") {
            Task { @MainActor in await RuntimeDiagnostics.testReopen() }
            return
        }
        if CommandLine.arguments.contains("--diagnose") {
            RuntimeDiagnostics.inspect()
            fflush(stdout)
            exit(0)
        }
        if CommandLine.arguments.contains("--test-panel-lifecycle") {
            Task { @MainActor in await PanelLifecycleTests.run() }
            return
        }
        coordinator = QueueCoordinator()
        floatingPanel = FloatingPanelController(coordinator: coordinator) { [weak self] in
            self?.showSettings()
        }
        shortcuts = GlobalShortcutMonitor(add: { [weak self] in self?.coordinator.addCurrent() }, toggle: { [weak self] in self?.floatingPanel.togglePanel() })
    }

    @objc private func showSettings() {
        floatingPanel.closePanel()
        if settingsWindow == nil {
            let view = SettingsView()
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 330), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "LitePark Settings"
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

}

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Add current Chat") { Text("⌃⌥L").monospaced() }
                LabeledContent("Open LitePark") { Text("⌃⌥K").monospaced() }
            }
            Section("Launch") {
                HStack {
                    Text("Launch at login")
                    Spacer()
                    Button(SMAppService.mainApp.status == .enabled ? "Enabled" : "Enable") {
                        try? SMAppService.mainApp.register()
                    }
                }
            }
            Section("Permissions") {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    Text(ChatGPTAX.trusted() ? "Allowed" : "Required")
                        .foregroundStyle(Color.laterAccent)
                    if !ChatGPTAX.trusted() {
                        Button("Open System Settings") { ChatGPTAX.openSettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(18)
    }
}

@main
struct ChatGPTLaterQueueApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
