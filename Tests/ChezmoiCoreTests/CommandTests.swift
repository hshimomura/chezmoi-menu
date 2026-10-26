import XCTest
@testable import ChezmoiCore

@MainActor
final class CommandTests: XCTestCase {
    func testShieldedCommandFinishesAfterCancellation() async throws {
        let task = Task {
            try await Command().runToCompletion("/bin/sleep", ["0.5"])
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = try await task.value
        XCTAssertEqual(result.code, 0)
    }
    func testTimeoutStopsProcessGroup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let start = ContinuousClock.now
        do {
            _ = try await Command().run("/bin/sh", ["-c", "(sleep 2; touch child-survived) & wait"], directory: root, timeout: 0.1)
            XCTFail("timeout ignored")
        } catch { XCTAssertTrue(error.localizedDescription.contains("タイムアウト")) }
        XCTAssertLessThan(start.duration(to: .now), .seconds(5))
        try await Task.sleep(for: .seconds(2.2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("child-survived").path))
    }

    func testCancellationIsReportedAsCancellation() async throws {
        let task = Task { try await Command().run("/bin/sleep", ["30"]) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; XCTFail("cancel ignored") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
