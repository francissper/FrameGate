//
//  UploadQueueTests.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

// swiftlint:disable file_length

import XCTest
@testable import FrameGateCore

final class UploadQueueTests: XCTestCase {

    private var directory: URL!
    private var clock: TestClock!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        clock = TestClock()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Creates a queue over the same directory.
    ///
    /// Calling this twice in a test simulates a relaunch after a force-quit:
    /// no in-memory state is handed from the old queue to the new one.
    private func makeQueue(
        _ transport: UploadTransport
    ) async throws -> UploadQueue {
        let queue = UploadQueue(
            journal: try Journal(
                url: directory.appendingPathComponent("queue.log")
            ),
            transport: transport,
            backoff: BackoffPolicy(
                base: 2,
                cap: 60,
                maxAttempts: 5,
                jitter: { 1.0 }
            ),
            clock: clock,
            storage: directory
        )

        try await queue.restore()

        return queue
    }

    private let manifest = Data("{}".utf8)
    private let frame = Data(repeating: 0xFF, count: 128)
}

// MARK: - Enqueue ordering

extension UploadQueueTests {

    func testTheCaptureIsOnDiskBeforeTheNetworkIsTouched() async throws {
        let transport = FakeTransport(script: [])
        let queue = try await makeQueue(transport)
        let captureID = UUID()

        try await queue.enqueue(
            manifest: manifest,
            frame: frame,
            captureID: captureID
        )

        // Enqueue only persists. It must not touch the network.
        XCTAssertTrue(transport.requests.isEmpty)

        // The record already survives a relaunch. This ordering is critical:
        // a crash after enqueue must not lose the capture.
        let reopened = try await makeQueue(transport)
        let records = await reopened.currentRecords

        XCTAssertEqual(
            records.map(\.captureID),
            [captureID]
        )

        XCTAssertEqual(
            records[0].status,
            .pending
        )
    }

    func testTheFrameFileIsWrittenBeforeTheRecord() async throws {
        let queue = try await makeQueue(
            FakeTransport(script: [])
        )
        let captureID = UUID()

        try await queue.enqueue(
            manifest: manifest,
            frame: frame,
            captureID: captureID
        )

        let record = await queue.currentRecords[0]

        let framePath = directory
            .appendingPathComponent(record.frameFilename)
            .path

        let manifestPath = directory
            .appendingPathComponent(record.manifestFilename)
            .path

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: framePath),
            "a record pointing at a missing frame is worse than no record"
        )

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: manifestPath)
        )
    }
}

// MARK: - Brief failure script

extension UploadQueueTests {

    /// The script suggested by the brief: 503, 503, timeout, 500, 201.
    private var suggestedScript: FakeTransport {
        FakeTransport(
            script: [
                .retryable(retryAfter: nil),
                .retryable(retryAfter: nil),
                .timedOut,
                .retryable(retryAfter: nil),
                .stored(duplicate: false)
            ]
        )
    }

    func testTheSuggestedScriptSucceedsOnTheFifthAttempt() async throws {
        let transport = suggestedScript
        let queue = try await makeQueue(transport)
        let captureID = UUID()

        try await queue.enqueue(
            manifest: manifest,
            frame: frame,
            captureID: captureID
        )

        // 2s, 4s, 8s and 16s between attempts. The test clock advances
        // explicitly, so the test never waits in real time.
        for delay in [0.0, 2, 4, 8, 16] {
            clock.advance(by: delay)
            await queue.drainOnce()
        }

        let record = await queue.currentRecords[0]

        XCTAssertEqual(
            record.status,
            .uploaded
        )

        XCTAssertEqual(
            record.attempts,
            5
        )

        XCTAssertEqual(
            transport.requests.count,
            5
        )
    }

    func testEveryAttemptCarriesTheSameIdempotencyKey() async throws {
        let transport = suggestedScript
        let queue = try await makeQueue(transport)
        let captureID = UUID()

        try await queue.enqueue(
            manifest: manifest,
            frame: frame,
            captureID: captureID
        )

        for delay in [0.0, 2, 4, 8, 16] {
            clock.advance(by: delay)
            await queue.drainOnce()
        }

        let keys = Set(
            transport.requests.map(\.idempotencyKey)
        )

        XCTAssertEqual(
            keys,
            [captureID],
            "a timeout leaves the outcome unknown; only an unchanged key "
                + "lets the server recognise the retry"
        )
    }

    func testNothingIsSentBeforeItsBackoffElapses() async throws {
        let transport = suggestedScript
        let queue = try await makeQueue(transport)

        try await queue.enqueue(
            manifest: manifest,
            frame: frame,
            captureID: UUID()
        )

        // Attempt one fails and schedules a two-second retry.
        await queue.drainOnce()

        XCTAssertEqual(
            transport.requests.count,
            1
        )

        clock.advance(by: 1)

        await queue.drainOnce()

        XCTAssertEqual(
            transport.requests.count,
            1,
            "the two-second backoff has not elapsed"
        )

        clock.advance(by: 1)

        await queue.drainOnce()

        XCTAssertEqual(
            transport.requests.count,
            2
        )
    }
}

// MARK: - Contract semantics

extension UploadQueueTests {

    func testADuplicateIsSuccessNotAResend() async throws {
        let transport = FakeTransport(
            script: [.stored(duplicate: true)]
        )
        let queue = try await makeQueue(transport)

        try await queue.enqueue(
            manifest: manifest,
            frame: frame,
            captureID: UUID()
        )

        await queue.drainOnce()
        await queue.drainOnce()

        let record = await queue.currentRecords[0]

        XCTAssertEqual(
            record.status,
            .uploaded
        )

        XCTAssertEqual(
            transport.requests.count,
            1,
            "the server already stored this key, so it must not be sent again"
        )
    }

    func testARejectionIsTerminalImmediately() async throws {
        let transport = FakeTransport(
            script: [.rejected]
        )
        let queue = try await makeQueue(transport)

        try await queue.enqueue(
            manifest: manifest,
            frame: frame,
            captureID: UUID()
        )

        await queue.drainOnce()

        let record = await queue.currentRecords[0]

        XCTAssertEqual(
            record.status,
            .failed
        )

        XCTAssertEqual(
            record.attempts,
            1,
            "a 422 must not consume the remaining automatic attempts"
        )

        clock.advance(by: 1_000)

        await queue.drainOnce()

        XCTAssertEqual(
            transport.requests.count,
            1,
            "a 422 must not be retried automatically"
        )
    }

    func testARetryAfterHintIsHonoured() async throws {
        let transport = FakeTransport(
            script: [.retryable(retryAfter: 30)]
        )
        let queue = try await makeQueue(transport)

        try await queue.enqueue(
            manifest: manifest,
            frame: frame,
            captureID: UUID()
        )

        await queue.drainOnce()

        // The exponential curve would allow a retry earlier, but Retry-After
        // takes precedence.
        clock.advance(by: 10)

        await queue.drainOnce()

        XCTAssertEqual(
            transport.requests.count,
            1,
            "the server requested a 30-second retry delay"
        )

        clock.advance(by: 25)

        await queue.drainOnce()

        XCTAssertEqual(
            transport.requests.count,
            2
        )
    }

    func testAttemptsAreBoundedThenTerminal() async throws {
        let transport = FakeTransport(
            script: [],
            thereafter: .retryable(retryAfter: nil)
        )
        let queue = try await makeQueue(transport)

        try await queue.enqueue(
            manifest: manifest,
            frame: frame,
            captureID: UUID()
        )

        for delay in [0.0, 2, 4, 8, 16, 32] {
            clock.advance(by: delay)
            await queue.drainOnce()
        }

        let record = await queue.currentRecords[0]

        XCTAssertEqual(
            record.status,
            .failed
        )

        XCTAssertEqual(
            transport.requests.count,
            5,
            "five attempts are allowed before the record becomes terminal"
        )
    }
}

// MARK: - Serial drain and ordering

extension UploadQueueTests {

    func testCapturesGoUpInTheOrderTheyWereTaken() async throws {
        let transport = FakeTransport(
            script: [],
            thereafter: .stored(duplicate: false)
        )
        let queue = try await makeQueue(transport)

        let first = UUID()
        let second = UUID()
        let third = UUID()

        for captureID in [first, second, third] {
            try await queue.enqueue(
                manifest: manifest,
                frame: frame,
                captureID: captureID
            )
        }

        await queue.drainOnce()
        await queue.drainOnce()
        await queue.drainOnce()

        XCTAssertEqual(
            transport.requests.map(\.idempotencyKey),
            [first, second, third]
        )
    }

    func testOneCallSendsOneCapture() async throws {
        let transport = FakeTransport(
            script: [],
            thereafter: .stored(duplicate: false)
        )
        let queue = try await makeQueue(transport)

        for _ in 0..<3 {
            try await queue.enqueue(
                manifest: manifest,
                frame: frame,
                captureID: UUID()
            )
        }

        await queue.drainOnce()

        XCTAssertEqual(
            transport.requests.count,
            1,
            "one drain call must process only one capture"
        )
    }

    func testConcurrentDrainCallsNeverOverlap() async throws {
        let transport = BlockingFirstTransport()
        let queue = try await makeQueue(transport)
        let captureID = UUID()

        try await queue.enqueue(
            manifest: manifest,
            frame: frame,
            captureID: captureID
        )

        let firstDrain = Task {
            await queue.drainOnce()
        }

        await transport.waitUntilFirstRequestStarts()

        let secondDrain = Task {
            await queue.drainOnce()
        }

        await secondDrain.value

        let requestCountWhileFirstIsSuspended =
            await transport.requestCount

        XCTAssertEqual(
            requestCountWhileFirstIsSuspended,
            1,
            "a second drain must not enter transport while the first is suspended"
        )

        await transport.finishFirst(
            with: .stored(duplicate: false)
        )

        await firstDrain.value

        let records = await queue.currentRecords

        XCTAssertEqual(
            records[0].status,
            .uploaded
        )

        XCTAssertEqual(
            records[0].attempts,
            1
        )
    }

    func testARecordWaitingOnBackoffDoesNotBlockTheNextOne() async throws {
        let transport = FakeTransport(
            script: [.retryable(retryAfter: nil)],
            thereafter: .stored(duplicate: false)
        )
        let queue = try await makeQueue(transport)

        let blocked = UUID()
        let behind = UUID()

        try await queue.enqueue(
            manifest: manifest,
            frame: frame,
            captureID: blocked
        )

        try await queue.enqueue(
            manifest: manifest,
            frame: frame,
            captureID: behind
        )

        // The first record fails and waits for backoff.
        await queue.drainOnce()

        // The second record is immediately due and should not be blocked.
        await queue.drainOnce()

        XCTAssertEqual(
            transport.requests.map(\.idempotencyKey),
            [blocked, behind]
        )
    }
}

// MARK: - Force-quit recovery

extension UploadQueueTests {

    func testAForceQuitMidUploadResendsExactlyOnce() async throws {
        let transport = FakeTransport(
            script: [.timedOut],
            thereafter: .stored(duplicate: true)
        )
        let captureID = UUID()

        try await persistAndTimeoutFirstSession(
            transport: transport,
            captureID: captureID
        )

        // Session two: a new queue reconstructs state only from disk.
        let relaunched = try await makeQueue(transport)
        let afterRelaunch = await relaunched.currentRecords[0]

        assertPendingAfterRelaunch(afterRelaunch)

        clock.advance(by: 2)

        await relaunched.drainOnce()

        // The retry reuses the same key. If the server stored the first
        // request before the timeout, it recognises the duplicate.
        let settled = await relaunched.currentRecords

        XCTAssertEqual(settled[0].status, .uploaded)
        assertSentExactlyOnceAfterDuplicateRetry(
            transport: transport,
            captureID: captureID
        )
    }

    private func persistAndTimeoutFirstSession(
        transport: FakeTransport,
        captureID: UUID
    ) async throws {
        let queue = try await makeQueue(transport)

        try await queue.enqueue(
            manifest: manifest,
            frame: frame,
            captureID: captureID
        )

        await queue.drainOnce()
    }

    private func assertPendingAfterRelaunch(_ record: CaptureRecord) {
        XCTAssertEqual(
            record.status,
            .pending,
            "nothing should remain stuck in an in-flight state"
        )

        XCTAssertEqual(
            record.attempts,
            1,
            "the timed-out attempt must still count"
        )
    }

    private func assertSentExactlyOnceAfterDuplicateRetry(
        transport: FakeTransport,
        captureID: UUID
    ) {
        let keys = transport.requests.map(\.idempotencyKey)

        XCTAssertEqual(
            keys,
            [captureID, captureID]
        )

        XCTAssertEqual(
            Set(keys).count,
            1,
            "every attempt must reuse the same idempotency key"
        )

        let stored = transport.requests.filter { request in
            if case .stored = request.outcome {
                return true
            }

            return false
        }

        XCTAssertEqual(
            stored.count,
            1,
            "the transport must report only one successful stored outcome"
        )
    }

    func testNothingIsLostAcrossRelaunch() async throws {
        let transport = FakeTransport(
            script: [],
            thereafter: .retryable(retryAfter: nil)
        )

        var captureIDs: [UUID] = []

        do {
            let queue = try await makeQueue(transport)

            for _ in 0..<3 {
                let captureID = UUID()
                captureIDs.append(captureID)

                try await queue.enqueue(
                    manifest: manifest,
                    frame: frame,
                    captureID: captureID
                )
            }
        }

        let relaunched = try await makeQueue(transport)
        let restored = await relaunched.currentRecords

        XCTAssertEqual(
            restored.map(\.captureID),
            captureIDs
        )
    }
}

// MARK: - Manual retry

extension UploadQueueTests {

    func testAManualRetryGivesAFailedRecordItsAttemptsBack() async throws {
        let transport = FakeTransport(
            script: [.rejected],
            thereafter: .stored(duplicate: false)
        )
        let queue = try await makeQueue(transport)
        let captureID = UUID()

        try await queue.enqueue(
            manifest: manifest,
            frame: frame,
            captureID: captureID
        )

        await queue.drainOnce()

        let afterFailure = await queue.currentRecords

        XCTAssertEqual(
            afterFailure[0].status,
            .failed
        )

        try await queue.retryManually(captureID)

        let retried = await queue.currentRecords[0]

        XCTAssertEqual(
            retried.status,
            .pending
        )

        XCTAssertEqual(
            retried.attempts,
            0,
            "a manual retry starts a fresh attempt budget"
        )

        await queue.drainOnce()

        let afterRetry = await queue.currentRecords

        XCTAssertEqual(
            afterRetry[0].status,
            .uploaded
        )
    }

    func testAManualRetryOnAnUploadedRecordDoesNothing() async throws {
        let transport = FakeTransport(
            script: [.stored(duplicate: false)]
        )
        let queue = try await makeQueue(transport)
        let captureID = UUID()

        try await queue.enqueue(
            manifest: manifest,
            frame: frame,
            captureID: captureID
        )

        await queue.drainOnce()

        try await queue.retryManually(captureID)

        let records = await queue.currentRecords

        XCTAssertEqual(
            records[0].status,
            .uploaded
        )

        XCTAssertEqual(
            transport.requests.count,
            1
        )
    }
}

// MARK: - Test transport

/// Suspends the first request until the test explicitly releases it.
///
/// This creates a deterministic window in which a second `drainOnce()` can
/// attempt to enter the queue while the first transport call is still awaiting.
private actor BlockingFirstTransport: UploadTransport {

    private var requests = 0

    private var firstRequestWaiters:
        [CheckedContinuation<Void, Never>] = []

    private var firstRequestContinuation:
        CheckedContinuation<UploadOutcome, Never>?

    var requestCount: Int {
        requests
    }

    func send(
        manifest: Data,
        frame: Data,
        idempotencyKey: UUID
    ) async -> UploadOutcome {
        requests += 1

        guard requests == 1 else {
            return .stored(duplicate: false)
        }

        let waiters = firstRequestWaiters
        firstRequestWaiters.removeAll()

        for waiter in waiters {
            waiter.resume()
        }

        return await withCheckedContinuation { continuation in
            firstRequestContinuation = continuation
        }
    }

    func waitUntilFirstRequestStarts() async {
        guard requests == 0 else {
            return
        }

        await withCheckedContinuation { continuation in
            firstRequestWaiters.append(continuation)
        }
    }

    func finishFirst(
        with outcome: UploadOutcome
    ) {
        firstRequestContinuation?.resume(
            returning: outcome
        )

        firstRequestContinuation = nil
    }
}
