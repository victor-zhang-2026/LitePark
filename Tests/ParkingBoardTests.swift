import AppKit

private var checks = 0
private var failures = 0
private func expect(_ condition: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line) rethrows {
    checks += 1
    if try !condition() { failures += 1; print("FAIL \(file):\(line)") }
}
private func expectEqual<T: Equatable>(_ actual: @autoclosure () throws -> T, _ expected: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) rethrows {
    try expect(actual() == expected(), file: file, line: line)
}
private func expectFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    expect(!value, file: file, line: line)
}
private func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    expect(value == nil, file: file, line: line)
}

final class ParkingBoardTests {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var file: URL { directory.appendingPathComponent("items.json") }

    func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "LitePark.Tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
    }

    private func store() -> LaterStore { LaterStore(fileURL: file, defaults: defaults) }
    private func fill(_ store: LaterStore, count: Int) {
        for i in 0..<count { expect(store.add(title: "Fixture \(i)")) }
    }

    func testDefaultAndEveryLimitPersistAndRejectOverflowWithoutWriting() throws {
        expectEqual(store().cardLimit, 12)
        expectEqual(LaterStore.cardLimits, [6, 9, 12, 16, 20])
        for limit in LaterStore.cardLimits {
            try? FileManager.default.removeItem(at: file)
            let current = store()
            current.cardLimit = limit
            fill(current, count: limit)
            let before = try Data(contentsOf: file)
            expectFalse(current.add(title: "Overflow"))
            expectFalse(current.add(title: current.items[0].title))
            try expectEqual(Data(contentsOf: file), before)
            let restarted = store()
            expectEqual(restarted.count, limit)
            expectEqual(restarted.cardLimit, limit)
            expectEqual(restarted.items, current.items)
        }
    }

    func testLowerLimitRetainsAllCardsAndOnlyResumesBelowLimit() throws {
        let current = store()
        fill(current, count: 12)
        let before = try Data(contentsOf: file)
        current.cardLimit = 6
        expectEqual(current.count, 12)
        try expectEqual(Data(contentsOf: file), before)
        expectEqual(store().items, current.items)
        expectFalse(current.add(title: "Blocked"))
        for _ in 0..<6 { _ = current.remove(at: 0) }
        expectFalse(current.add(title: "Still full"))
        _ = current.remove(at: 0)
        expect(current.add(title: "Space available"))
        expectEqual(current.count, 6)
    }

    func testExistingOverLimitDataLoadsWithoutLoss() throws {
        let items = (0..<25).map { LaterItem(id: UUID(), title: "Legacy \($0)", addedAt: Date(), order: $0) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = try JSONEncoder().encode(items)
        try original.write(to: file)
        let current = store()
        expectEqual(current.cardLimit, 12)
        expectEqual(current.items, items)
        expectFalse(current.add(title: "Blocked"))
        try expectEqual(Data(contentsOf: file), original)
    }

    func testDoneUndoRestoresOriginalPositionEvenAboveLimit() {
        let current = store()
        fill(current, count: 12)
        current.cardLimit = 6
        let original = current.items
        let coordinator = QueueCoordinator(store: current)
        coordinator.done(original[4])
        expectEqual(current.count, 11)
        expect(coordinator.canUndo)
        coordinator.undo()
        expectEqual(current.items, original)
        expectEqual(store().items, original)
        expectFalse(coordinator.canUndo)
    }

    func testFullAddShowsNonmodalFeedbackWithoutCapture() {
        let current = store()
        current.cardLimit = 6
        fill(current, count: 6)
        let original = current.items
        let coordinator = QueueCoordinator(store: current)
        coordinator.addCurrent()
        expect(coordinator.limitReached)
        expectEqual(coordinator.islandState, .expanded)
        expectEqual(current.items, original)
    }

    func testGridReordersAcrossColumnsRowsAndPersistsOnlyOnRelease() throws {
        let current = store()
        fill(current, count: 9)
        let coordinator = QueueCoordinator(store: current)
        func frames() {
            coordinator.rowFrames = Dictionary(uniqueKeysWithValues: current.items.enumerated().map {
                ($0.element.id, CGRect(x: ($0.offset % 2) * 202 + 14, y: ($0.offset / 2) * 98 + 14, width: 192, height: 88))
            })
        }
        for (source, destination) in [(0, 1), (1, 6), (8, 0), (0, 8)] {
            frames()
            let original = current.items
            let before = try Data(contentsOf: file)
            let moving = original[source]
            let target = coordinator.rowFrames[original[destination].id]!
            coordinator.updateReorder(moving.id, at: CGPoint(x: target.midX, y: target.midY))
            expectEqual(coordinator.reorderPreview?[destination].id, moving.id)
            expectEqual(current.items, original)
            try expectEqual(Data(contentsOf: file), before)
            coordinator.finishReorder()
            expectEqual(current.items[destination].id, moving.id)
            expectEqual(Set(current.items.map(\.id)), Set(original.map(\.id)))
            expectEqual(current.items.map(\.order), Array(0..<9))
            expectEqual(store().items, current.items)
            expectNil(coordinator.draggingID)
            expectNil(coordinator.reorderPreview)
        }
        frames()
        let beforeCancel = current.items
        coordinator.updateReorder(current.items[0].id, at: CGPoint(x: 110, y: 450))
        coordinator.cancelReorder()
        expectEqual(current.items, beforeCancel)
    }
}

@main
struct ParkingBoardTestRunner {
    static func main() throws {
        _ = NSApplication.shared
        let test = ParkingBoardTests()
        let cases: [(String, () throws -> Void)] = [
            ("limits and persistence", test.testDefaultAndEveryLimitPersistAndRejectOverflowWithoutWriting),
            ("lower limit preserves cards", test.testLowerLimitRetainsAllCardsAndOnlyResumesBelowLimit),
            ("legacy over-limit data", test.testExistingOverLimitDataLoadsWithoutLoss),
            ("Done and Undo above limit", test.testDoneUndoRestoresOriginalPositionEvenAboveLimit),
            ("full Add feedback", test.testFullAddShowsNonmodalFeedbackWithoutCapture),
            ("grid reorder and restart", test.testGridReordersAcrossColumnsRowsAndPersistsOnlyOnRelease)
        ]
        for (name, run) in cases {
            test.setUp()
            defer { test.tearDown() }
            let before = failures
            try run()
            print("\(failures == before ? "PASS" : "FAIL") \(name)")
        }
        print("PARKING_BOARD_CHECKS=\(checks) FAILURES=\(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
