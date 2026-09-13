//
//  UploadQueueTests.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import XCTest
@testable import FrameGateCore

final class UploadQueueTests: XCTestCase {

    private var directory: URL!
    private var clock: TestClock!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        clock = TestClock()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A queue over the same directory. Called twice in a test to stand in for
    /// relaunch after a force-quit: nothing is handed over in memory.
    private func makeQueue(_ transport: UploadTransport) async throws -> UploadQueue {
        let queue = UploadQueue(
            journal: try Journal(url: directory.appendingPathComponent("queue.log")),
            transport: transport,
            backoff: BackoffPolicy(base: 2, cap: 60, maxAttempts: 5, jitter: { 1.0 }),
            clock: clock,
            storage: directory
        )
        try await queue.restore()
        return queue
    }

    private let manifest = Data("{}".utf8)
    private let frame = Data(repeating: 0xFF, count: 128)
}

// MARK: - El orden al encolar

extension UploadQueueTests {

    func testTheCaptureIsOnDiskBeforeTheNetworkIsTouched() async throws {
        let transport = FakeTransport(script: [])
        let queue = try await makeQueue(transport)
        let captureID = UUID()

        try await queue.enqueue(manifest: manifest, frame: frame, captureID: captureID)

        // Nothing has been sent: enqueue only persists.
        XCTAssertTrue(transport.requests.isEmpty)

        // But the record survives already. This is the ordering the whole design
        // rests on: a crash here loses nothing.
        let reopened = try await makeQueue(transport)
        let records = await reopened.currentRecords
        XCTAssertEqual(records.map(\.captureID), [captureID])
        XCTAssertEqual(records[0].status, .pending)
    }

    func testTheFrameFileIsWrittenBeforeTheRecord() async throws {
        let queue = try await makeQueue(FakeTransport(script: []))
        let captureID = UUID()

        try await queue.enqueue(manifest: manifest, frame: frame, captureID: captureID)

        let record = await queue.currentRecords[0]
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.framePath),
                      "a record pointing at a file that is not there is worse than no record")
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.manifestPath))
    }
}

// MARK: - El guion del brief

extension UploadQueueTests {

    /// The script the brief suggests: 503, 503, timeout, 500, 201.
    private var suggestedScript: FakeTransport {
        FakeTransport(script: [
            .retryable(retryAfter: nil),
            .retryable(retryAfter: nil),
            .timedOut,
            .retryable(retryAfter: nil),
            .stored(duplicate: false)
        ])
    }

    func testTheSuggestedScriptSucceedsOnTheFifthAttempt() async throws {
        let transport = suggestedScript
        let queue = try await makeQueue(transport)
        let captureID = UUID()
        try await queue.enqueue(manifest: manifest, frame: frame, captureID: captureID)

        // 2s, 4s, 8s, 16s between attempts — advanced by hand, never waited.
        for delay in [0.0, 2, 4, 8, 16] {
            clock.advance(by: delay)
            await queue.drainOnce()
        }

        let record = await queue.currentRecords[0]
        XCTAssertEqual(record.status, .uploaded)
        XCTAssertEqual(record.attempts, 5)
        XCTAssertEqual(transport.requests.count, 5)
    }

    func testEveryAttemptCarriesTheSameIdempotencyKey() async throws {
        let transport = suggestedScript
        let queue = try await makeQueue(transport)
        let captureID = UUID()
        try await queue.enqueue(manifest: manifest, frame: frame, captureID: captureID)

        for delay in [0.0, 2, 4, 8, 16] {
            clock.advance(by: delay)
            await queue.drainOnce()
        }

        let keys = Set(transport.requests.map(\.idempotencyKey))
        XCTAssertEqual(keys, [captureID],
                       "a timeout leaves the outcome unknown; only an unchanged key "
                       + "lets the server recognise the retry")
    }

    func testNothingIsSentBeforeItsBackoffElapses() async throws {
        let transport = suggestedScript
        let queue = try await makeQueue(transport)
        try await queue.enqueue(manifest: manifest, frame: frame, captureID: UUID())

        await queue.drainOnce()                    // attempt 1, fails
        XCTAssertEqual(transport.requests.count, 1)

        clock.advance(by: 1)                       // not yet due
        await queue.drainOnce()
        XCTAssertEqual(transport.requests.count, 1, "the 2s wait is not up")

        clock.advance(by: 1)                       // now it is
        await queue.drainOnce()
        XCTAssertEqual(transport.requests.count, 2)
    }
}

// MARK: - Las semánticas del contrato

extension UploadQueueTests {

    func testADuplicateIsSuccessNotAResend() async throws {
        let transport = FakeTransport(script: [.stored(duplicate: true)])
        let queue = try await makeQueue(transport)
        try await queue.enqueue(manifest: manifest, frame: frame, captureID: UUID())

        await queue.drainOnce()
        await queue.drainOnce()

        let record = await queue.currentRecords[0]
        XCTAssertEqual(record.status, .uploaded)
        XCTAssertEqual(transport.requests.count, 1,
                       "the server already had it; sending again would be pointless")
    }

    func testARejectionIsTerminalImmediately() async throws {
        let transport = FakeTransport(script: [.rejected])
        let queue = try await makeQueue(transport)
        try await queue.enqueue(manifest: manifest, frame: frame, captureID: UUID())

        await queue.drainOnce()

        let record = await queue.currentRecords[0]
        XCTAssertEqual(record.status, .failed)
        XCTAssertEqual(record.attempts, 1, "422 does not get the other four attempts")

        clock.advance(by: 1000)
        await queue.drainOnce()
        XCTAssertEqual(transport.requests.count, 1, "no automatic retry after 422")
    }

    func testARetryAfterHintIsHonoured() async throws {
        let transport = FakeTransport(script: [.retryable(retryAfter: 30)])
        let queue = try await makeQueue(transport)
        try await queue.enqueue(manifest: manifest, frame: frame, captureID: UUID())

        await queue.drainOnce()

        clock.advance(by: 10)                      // the curve would say 2s
        await queue.drainOnce()
        XCTAssertEqual(transport.requests.count, 1, "the server said 30")

        clock.advance(by: 25)
        await queue.drainOnce()
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testAttemptsAreBoundedThenTerminal() async throws {
        let transport = FakeTransport(script: [], thereafter: .retryable(retryAfter: nil))
        let queue = try await makeQueue(transport)
        try await queue.enqueue(manifest: manifest, frame: frame, captureID: UUID())

        for delay in [0.0, 2, 4, 8, 16, 32] {
            clock.advance(by: delay)
            await queue.drainOnce()
        }

        let record = await queue.currentRecords[0]
        XCTAssertEqual(record.status, .failed)
        XCTAssertEqual(transport.requests.count, 5, "five attempts, then stop")
    }
}

// MARK: - El drain serial y el orden

extension UploadQueueTests {

    func testCapturesGoUpInTheOrderTheyWereTaken() async throws {
        let transport = FakeTransport(script: [], thereafter: .stored(duplicate: false))
        let queue = try await makeQueue(transport)
        let first = UUID(), second = UUID(), third = UUID()

        for id in [first, second, third] {
            try await queue.enqueue(manifest: manifest, frame: frame, captureID: id)
        }

        await queue.drainOnce()
        await queue.drainOnce()
        await queue.drainOnce()

        XCTAssertEqual(transport.requests.map(\.idempotencyKey), [first, second, third])
    }

    func testOneCallSendsOneCapture() async throws {
        let transport = FakeTransport(script: [], thereafter: .stored(duplicate: false))
        let queue = try await makeQueue(transport)
        for _ in 0..<3 {
            try await queue.enqueue(manifest: manifest, frame: frame, captureID: UUID())
        }

        await queue.drainOnce()

        XCTAssertEqual(transport.requests.count, 1, "serial: one at a time, never overlapping")
    }

    func testARecordWaitingOnBackoffDoesNotBlockTheNextOne() async throws {
        let transport = FakeTransport(script: [.retryable(retryAfter: nil)],
                                      thereafter: .stored(duplicate: false))
        let queue = try await makeQueue(transport)
        let blocked = UUID(), behind = UUID()

        try await queue.enqueue(manifest: manifest, frame: frame, captureID: blocked)
        try await queue.enqueue(manifest: manifest, frame: frame, captureID: behind)

        await queue.drainOnce()                    // first fails, now waiting 2s
        await queue.drainOnce()                    // second should go anyway

        XCTAssertEqual(transport.requests.map(\.idempotencyKey), [blocked, behind])
    }
}

// MARK: - El de force-quit

extension UploadQueueTests {

    func testAForceQuitMidUploadResendsExactlyOnce() async throws {
        let transport = FakeTransport(script: [.timedOut],
                                      thereafter: .stored(duplicate: true))
        let captureID = UUID()

        // Session one: the capture is written, the POST goes out, no response
        // comes back — and then the process dies.
        do {
            let queue = try await makeQueue(transport)
            try await queue.enqueue(manifest: manifest, frame: frame, captureID: captureID)
            await queue.drainOnce()
        }

        // Session two: a fresh queue over the same journal, nothing handed over.
        let relaunched = try await makeQueue(transport)
        let afterRelaunch = await relaunched.currentRecords[0]

        XCTAssertEqual(afterRelaunch.status, .pending,
                       "nothing is stuck in flight: there is no in-flight state to be stuck in")
        XCTAssertEqual(afterRelaunch.attempts, 1, "the attempt that timed out still counts")

        clock.advance(by: 2)
        await relaunched.drainOnce()

        // The second attempt reuses the key, the server recognises it, and the
        // record settles as uploaded. The shot went up once.
        let settled = await relaunched.currentRecords
        XCTAssertEqual(settled[0].status, .uploaded)

        let keys = transport.requests.map(\.idempotencyKey)
        XCTAssertEqual(keys, [captureID, captureID])
        XCTAssertEqual(Set(keys).count, 1, "no duplicate key in the log")

        let stored = transport.requests.filter {
            if case .stored = $0.outcome { return true }
            return false
        }
        XCTAssertEqual(stored.count, 1, "sent exactly once")
    }

    func testNothingIsLostAcrossRelaunch() async throws {
        let transport = FakeTransport(script: [], thereafter: .retryable(retryAfter: nil))
        var ids: [UUID] = []

        do {
            let queue = try await makeQueue(transport)
            for _ in 0..<3 {
                let id = UUID()
                ids.append(id)
                try await queue.enqueue(manifest: manifest, frame: frame, captureID: id)
            }
        }

        let relaunched = try await makeQueue(transport)
        let restored = await relaunched.currentRecords
        XCTAssertEqual(restored.map(\.captureID), ids)
    }
}

// MARK: - El reintento manual

extension UploadQueueTests {

    func testAManualRetryGivesAFailedRecordItsAttemptsBack() async throws {
        let transport = FakeTransport(script: [.rejected],
                                      thereafter: .stored(duplicate: false))
        let queue = try await makeQueue(transport)
        let captureID = UUID()
        try await queue.enqueue(manifest: manifest, frame: frame, captureID: captureID)

        await queue.drainOnce()
        let afterFailure = await queue.currentRecords
        XCTAssertEqual(afterFailure[0].status, .failed)

        try await queue.retryManually(captureID)

        let retried = await queue.currentRecords[0]
        XCTAssertEqual(retried.status, .pending)
        XCTAssertEqual(retried.attempts, 0, "a manual retry starts the budget over")

        await queue.drainOnce()
        let afterRetry = await queue.currentRecords
        XCTAssertEqual(afterRetry[0].status, .uploaded)
    }

    func testAManualRetryOnAnUploadedRecordDoesNothing() async throws {
        let transport = FakeTransport(script: [.stored(duplicate: false)])
        let queue = try await makeQueue(transport)
        let captureID = UUID()
        try await queue.enqueue(manifest: manifest, frame: frame, captureID: captureID)
        await queue.drainOnce()

        try await queue.retryManually(captureID)

        let records = await queue.currentRecords
        XCTAssertEqual(records[0].status, .uploaded)
        XCTAssertEqual(transport.requests.count, 1)
    }
}
