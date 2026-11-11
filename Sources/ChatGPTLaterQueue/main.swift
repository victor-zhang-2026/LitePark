import AppKit
import SwiftUI
import Combine
import ApplicationServices
import ServiceManagement
import Carbon.HIToolbox
import UniformTypeIdentifiers

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
    static let cardLimits = [6, 9, 12, 16, 20]
    @Published var cardLimit: Int {
        didSet { defaults.set(cardLimit, forKey: "cardLimit") }
    }
    @Published private(set) var items: [LaterItem] = []
    private let fileURL: URL
    private let defaults: UserDefaults

    init(fileURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedLimit = defaults.integer(forKey: "cardLimit")
        cardLimit = Self.cardLimits.contains(savedLimit) ? savedLimit : 12
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = base.appendingPathComponent("ChatGPTLaterQueue/items.json")
        }
        load()
    }

    var count: Int { items.count }
    var isFull: Bool { count >= cardLimit }

    func contains(title: String) -> Bool {
        items.contains { $0.title == title }
    }

    @discardableResult
    func add(title: String) -> Bool {
        guard !contains(title: title), !isFull else { return false }
        let item = LaterItem(id: UUID(), title: title, addedAt: Date(), order: 0)
        items.insert(item, at: 0)
        normalize()
        save()
        return true
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
    @Published private(set) var reorderPreview: [LaterItem]?
    @Published private(set) var limitReached = false
    private var limitFeedbackWork: DispatchWorkItem?
    private var dragSlots: [CGRect] = []
    var rowFrames: [UUID: CGRect] = [:]
    private var storeSubscription: AnyCancellable?

    init(store: LaterStore = LaterStore()) {
        self.store = store
        storeSubscription = store.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    func updateReorder(_ id: UUID, at point: CGPoint) {
        if draggingID == nil {
            guard store.items.contains(where: { $0.id == id }) else { return }
            // Keep slot geometry stable while the preview makes room for the card.
            dragSlots = store.items.compactMap { rowFrames[$0.id] }
            guard dragSlots.count == store.count else { return }
            reorderPreview = store.items
            draggingID = id
        }
        guard draggingID == id, var preview = reorderPreview,
              let source = preview.firstIndex(where: { $0.id == id }),
              let target = dragSlots.indices.min(by: {
                  hypot(point.x - dragSlots[$0].midX, point.y - dragSlots[$0].midY) <
                  hypot(point.x - dragSlots[$1].midX, point.y - dragSlots[$1].midY)
              }), source != target else { return }
        let item = preview.remove(at: source)
        preview.insert(item, at: target)
        reorderPreview = preview
    }

    func finishReorder() {
        defer { cancelReorder() }
        guard let id = draggingID, let preview = reorderPreview,
              let index = preview.firstIndex(where: { $0.id == id }),
              store.items.map(\.id) != preview.map(\.id) else { return }
        store.move(id, before: index + 1 < preview.count ? preview[index + 1].id : nil)
    }

    func cancelReorder() {
        if draggingID != nil { NSCursor.arrow.set() }
        draggingID = nil
        reorderPreview = nil
        dragSlots = []
    }

    private func showLimitFeedback() {
        limitFeedbackWork?.cancel()
        limitReached = true
        islandState = .expanded
        let work = DispatchWorkItem { [weak self] in self?.limitReached = false }
        limitFeedbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private var isCapturing = false

    func addCurrent() {
        guard !isCapturing else { return }
        guard !store.isFull else { showLimitFeedback(); return }
        isCapturing = true
        Task { @MainActor in
            defer { isCapturing = false }
            do {
                let title = try await ChatGPTAX.captureTitleForAdd()
                if store.contains(title: title) {
                    RuntimeLog.write("add duplicate ignored")
                } else {
                    if store.add(title: title) {
                        RuntimeLog.write("add saved")
                    } else if store.isFull {
                        showLimitFeedback()
                    }
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
    private let floatingPlacement = FloatingPlacement()
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
    private var isAppearanceTransitioning = false
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

    func transitionAppearance(_ change: @escaping () -> Void) {
        guard !isAppearanceTransitioning else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let contentView = panel.contentView,
              contentView.bounds.width > 0, contentView.bounds.height > 0,
              let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            change()
            return
        }
        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
        let image = NSImage(size: contentView.bounds.size)
        image.addRepresentation(bitmap)
        let snapshot = NSImageView(frame: contentView.bounds)
        snapshot.image = image
        snapshot.imageScaling = .scaleAxesIndependently
        contentView.addSubview(snapshot)
        isAppearanceTransitioning = true
        change()
        DispatchQueue.main.async { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.26
                snapshot.animator().alphaValue = 0
            }, completionHandler: {
                DispatchQueue.main.async {
                    snapshot.removeFromSuperview()
                    self?.isAppearanceTransitioning = false
                }
            })
        }
    }

    func showTrigger() {
        floatingPlacement.restore(triggerPanel, fallback: savedTriggerOrigin())
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
        coordinator.cancelReorder()
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
        guard !draggingTrigger else { return }
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
                  self.coordinator.draggingID == nil, !self.draggingTrigger else { return }
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

    func moveTrigger(to proposed: NSPoint, ended: Bool) {
        draggingTrigger = true
        closeWork?.cancel()
        triggerPanel.setFrameOrigin(proposed)
        if ended {
            let pointer = NSEvent.mouseLocation
            let proposedFrame = NSRect(origin: proposed, size: triggerSize)
            let screens = NSScreen.screens
            let screenIndex = TriggerPlacement.screenIndex(mouse: pointer, window: proposedFrame, screens: screens.map(\.frame))
            let screen = screenIndex.map { screens[$0] } ?? NSScreen.main ?? screens.first!
            let settled = constrainedTriggerOrigin(proposed, to: screen)
            RuntimeLog.write("trigger drag ended proposed=\(proposed) pointer=\(pointer) screen=\(screen.frame) visible=\(screen.visibleFrame) settled=\(settled)")
            triggerPanel.setFrameOrigin(settled)
            UserDefaults.standard.set(Double(settled.x), forKey: "triggerX")
            UserDefaults.standard.set(Double(settled.y), forKey: "triggerY")
            floatingPlacement.remember(triggerPanel)
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
        panel.hasShadow = true
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
        coordinator.store.count == 0 ? 190 : 54 + QueueView.boardHeight(for: coordinator.store.count, limit: coordinator.store.cardLimit)
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

    @objc private func displayParametersChanged() {
        floatingPlacement.afterScreenChange { [weak self] in
            guard let self, !self.draggingTrigger else { return }
            self.showTrigger(); if self.isShown { self.refreshPanel() }
        }
    }

    private func screenContaining(_ frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    private func screenBestMatching(_ frame: NSRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard let index = TriggerPlacement.bestScreenIndex(window: frame, screens: screens.map(\.frame)) else { return nil }
        return screens[index]
    }

    private func constrainedTriggerOrigin(_ origin: NSPoint, to screen: NSScreen) -> NSPoint {
        TriggerPlacement.clamp(origin, size: triggerSize, visibleFrame: screen.visibleFrame)
    }

    private func savedTriggerOrigin() -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        if UserDefaults.standard.object(forKey: "triggerX") != nil {
            let origin = NSPoint(x: UserDefaults.standard.double(forKey: "triggerX"), y: UserDefaults.standard.double(forKey: "triggerY"))
            let savedFrame = NSRect(origin: origin, size: triggerSize)
            return constrainedTriggerOrigin(origin, to: screenBestMatching(savedFrame) ?? screen)
        }
        let origin = NSPoint(x: screen.visibleFrame.maxX - triggerSize.width - 12, y: screen.visibleFrame.midY - triggerSize.height / 2)
        return constrainedTriggerOrigin(origin, to: screen)
    }

}

final class FloatingTriggerView: NSView {
    weak var controller: FloatingPanelController?
    var count = 0 { didSet { needsDisplay = true } }
    private var startPoint: NSPoint?
    private var startOrigin: NSPoint?
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
    override func mouseDown(with event: NSEvent) {
        startPoint = NSEvent.mouseLocation
        startOrigin = window?.frame.origin
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let startPoint, let startOrigin else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - startPoint.x, dy = current.y - startPoint.y
        if !dragged && hypot(dx, dy) <= 3 { return }
        dragged = true
        controller?.moveTrigger(to: NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy), ended: false)
    }
    override func mouseUp(with event: NSEvent) {
        if dragged, let startPoint, let startOrigin {
            let pointer = NSEvent.mouseLocation
            controller?.moveTrigger(to: NSPoint(x: startOrigin.x + pointer.x - startPoint.x, y: startOrigin.y + pointer.y - startPoint.y), ended: true)
        } else {
            controller?.openFromTriggerClick()
        }
        startPoint = nil; startOrigin = nil
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
    @AppStorage("appAppearance") private var appearanceRawValue = AppearanceMode.dark.rawValue
    let controller: FloatingPanelController
    let onSettings: () -> Void

    private var appearanceMode: AppearanceMode { AppearanceMode(rawValue: appearanceRawValue) ?? .dark }

    var body: some View {
        Group {
            switch coordinator.islandState {
            case .idle: expanded
            case .expanded: expanded
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { controller.listHoverChanged($0) }
        .preferredColorScheme(appearanceMode.colorScheme)
        .onAppear { NSApp.appearance = appearanceMode.nativeAppearance }
        .onChange(of: appearanceRawValue) { _ in NSApp.appearance = appearanceMode.nativeAppearance }
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 11) {
                    Image(nsImage: BrandArtwork.headerImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                    Text("LitePark")
                        .font(.system(size: 15, weight: .semibold))
                }
                Spacer()
                Text("\(coordinator.store.count) / \(coordinator.store.cardLimit)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.laterInk.opacity(0.70))
                Button {
                    controller.transitionAppearance {
                        appearanceRawValue = appearanceMode == .light
                            ? AppearanceMode.dark.rawValue : AppearanceMode.light.rawValue
                    }
                } label: {
                    Image(systemName: appearanceMode.symbolName)
                        .foregroundStyle(Color.laterInk.opacity(0.78))
                }
                .buttonStyle(ParkHeaderButtonStyle())
                .parkFastHelp(appearanceMode.toggleLabel)
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(Color.laterInk.opacity(0.78))
                }.buttonStyle(ParkHeaderButtonStyle()).parkFastHelp("Settings")
                Button { coordinator.collapse() } label: {
                    Image(systemName: "xmark").foregroundStyle(Color.laterInk.opacity(0.78))
                }.buttonStyle(ParkHeaderButtonStyle(hoverColor: .red)).parkFastHelp("Close LitePark", horizontalOffset: -30)
            }
            .foregroundStyle(Color.laterInk)
            .padding(.horizontal, 18).frame(height: 54)
            .zIndex(10)
        .background(Color.laterElevated)
        QueueView(coordinator: coordinator)
        }
        .background(Color.laterSurface)
        .overlay(alignment: .bottom) {
            if coordinator.limitReached {
                Text("Card limit reached.")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.laterElevated, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.laterAccent.opacity(0.4)))
                    .padding(12)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Card limit reached. Finish a card before adding another.")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(appearanceMode == .light ? Color.black.opacity(0.10) : Color.laterSeparator, lineWidth: appearanceMode == .light ? 0.5 : 1)
        }
        .frame(width: 420, alignment: .top)
    }
}

private struct ParkHeaderButtonStyle: ButtonStyle {
    var hoverColor: Color = .primary
    func makeBody(configuration: Configuration) -> some View {
        ParkHeaderButtonBody(configuration: configuration, hoverColor: hoverColor)
    }
    private struct ParkHeaderButtonBody: View {
        let configuration: Configuration
        let hoverColor: Color
        @State private var hovering = false
        var body: some View {
            configuration.label
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .background(hoverColor.opacity(configuration.isPressed ? 0.12 : hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

private struct ParkFastHelpModifier: ViewModifier {
    let text: String
    let horizontalOffset: CGFloat
    @State private var isPresented = false
    @State private var hoverToken = UUID()
    func body(content: Content) -> some View {
        content
            .accessibilityLabel(text)
            .onHover { hovering in
                let token = UUID()
                hoverToken = token
                if hovering {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        guard hoverToken == token else { return }
                        isPresented = true
                    }
                } else { isPresented = false }
            }
            .overlay(alignment: .bottom) {
                if isPresented {
                    Text(text)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.laterInk)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.laterSeparator, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                        .offset(x: horizontalOffset, y: 28)
                        .allowsHitTesting(false)
                }
            }
            .zIndex(isPresented ? 20 : 0)
    }
}

private extension View {
    func parkFastHelp(_ text: String, horizontalOffset: CGFloat = 0) -> some View {
        modifier(ParkFastHelpModifier(text: text, horizontalOffset: horizontalOffset))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: QueueCoordinator!
    private var floatingPanel: FloatingPanelController!
    private var shortcuts: GlobalShortcutMonitor!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let appearance = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appAppearance") ?? "") ?? .dark
        NSApp.appearance = appearance.nativeAppearance
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
            let view = SettingsView(store: coordinator.store)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 430), styleMask: [.titled, .closable], backing: .buffered, defer: false)
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
    @ObservedObject var store: LaterStore
    @AppStorage("appAppearance") private var appearanceRawValue = AppearanceMode.dark.rawValue

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
            Section {
                Picker("Card Limit", selection: $store.cardLimit) {
                    ForEach(LaterStore.cardLimits, id: \.self) { limit in
                        Text("\(limit)").tag(limit)
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
        .preferredColorScheme((AppearanceMode(rawValue: appearanceRawValue) ?? .dark).colorScheme)
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
