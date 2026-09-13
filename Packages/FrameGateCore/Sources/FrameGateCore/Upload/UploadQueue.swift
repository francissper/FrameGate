//
//  UploadQueue.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

@preconcurrency import Combine
import Foundation

/// Drains captures to the server one at a time.
///
/// An actor rather than a serial queue: the brief asks for a serial drain, and
/// an actor gives that without any lock discipline to get wrong. Every mutation
/// of the record set happens inside it.
public actor UploadQueue {

    private let journal: Journal
    private let transport: UploadTransport
    private let backoff: BackoffPolicy
    private let clock: Clock
    private let storage: URL

    private var records: [CaptureRecord] = []
    nonisolated(unsafe) private let recordsSubject = CurrentValueSubject<[CaptureRecord], Never>([])

    public init(journal: Journal,
                transport: UploadTransport,
                backoff: BackoffPolicy = BackoffPolicy(),
                clock: Clock = SystemClock(),
                storage: URL) {
        self.journal = journal
        self.transport = transport
        self.backoff = backoff
        self.clock = clock
        self.storage = storage
    }

    /// Rebuilds state from the journal. Anything that was mid-upload when the
    /// process died is already `pending` — there is no recovery pass because
    /// there is no `uploading` state to recover from.
    public func restore() throws {
        records = try journal.replay()
        recordsSubject.send(records)
    }

    /// The Queue screen's stream.
    public nonisolated var state: AnyPublisher<[CaptureRecord], Never> {
        recordsSubject.eraseToAnyPublisher()
    }

    /// Writes the frame and the record to disk, then returns. The network is not
    /// touched here: once this returns, the capture survives a force-quit.
    public func enqueue(manifest: Data, frame: Data, captureID: UUID) throws {
        let framePath = storage.appendingPathComponent("\(captureID.uuidString).jpg")
        let manifestPath = storage.appendingPathComponent("\(captureID.uuidString).json")

        // Files first: a record pointing at a file that is not there would be
        // worse than no record at all.
        try frame.write(to: framePath, options: .atomic)
        try manifest.write(to: manifestPath, options: .atomic)

        try journal.append(.captured(captureID: captureID,
                                     manifestPath: manifestPath.path,
                                     framePath: framePath.path,
                                     at: clock.now))

        records.append(CaptureRecord(captureID: captureID,
                                     manifestPath: manifestPath.path,
                                     framePath: framePath.path))
        recordsSubject.send(records)
    }

    /// Sends whatever is due. One attempt per call, one record at a time.
    public func drainOnce() async {
        guard let index = nextDueIndex() else { return }

        let record = records[index]
        let attempt = record.attempts + 1

        guard let manifest = FileManager.default.contents(atPath: record.manifestPath),
              let frame = FileManager.default.contents(atPath: record.framePath) else {
            return
        }

        // The attempted event is written before the await. If the process dies
        // during the request, the attempt is already counted and the record
        // stays pending — no recovery pass needed.
        try? journal.append(.attempted(captureID: record.captureID,
                                       attempt: attempt,
                                       at: clock.now))
        records[index].attempts = attempt
        recordsSubject.send(records)

        let outcome = await transport.send(manifest: manifest,
                                           frame: frame,
                                           idempotencyKey: record.captureID)

        apply(outcome, toRecordWith: record.captureID, attempt: attempt)
    }

    /// Puts a failed record back in line with its attempts reset.
    public func retryManually(_ captureID: UUID) throws {
        guard let index = records.firstIndex(where: { $0.captureID == captureID }),
              records[index].status == .failed else { return }

        try journal.append(.manuallyRetried(captureID: captureID, at: clock.now))

        records[index].status = .pending
        records[index].attempts = 0
        records[index].nextAttemptAt = nil
        recordsSubject.send(records)
    }

    public var currentRecords: [CaptureRecord] { records }
}

// MARK: - Private helpers

private extension UploadQueue {

    /// The first record whose backoff has elapsed. A record still waiting does
    /// not block the ones behind it.
    func nextDueIndex() -> Int? {
        records.firstIndex { record in
            guard record.status == .pending else { return false }
            guard let due = record.nextAttemptAt else { return true }
            return due <= clock.now
        }
    }

    func apply(_ outcome: UploadOutcome, toRecordWith captureID: UUID, attempt: Int) {
        guard let index = records.firstIndex(where: { $0.captureID == captureID }) else {
            return
        }

        switch outcome {
        case .stored:
            // A duplicate flag means the server already had this key — the work
            // is done either way, so both settle the same.
            try? journal.append(.uploaded(captureID: captureID, at: clock.now))
            records[index].status = .uploaded
            records[index].nextAttemptAt = nil

        case .rejected:
            // 422 does not get the remaining attempts: the payload is wrong and
            // sending it again would be wrong the same way.
            try? journal.append(.failed(captureID: captureID, at: clock.now))
            records[index].status = .failed
            records[index].nextAttemptAt = nil

        case .retryable(let hint):
            schedule(index: index, attempt: attempt, hint: hint, captureID: captureID)

        case .timedOut:
            // Retryable, but the shot may in fact have been stored. Only an
            // unchanged key lets the server tell us so on the next attempt.
            schedule(index: index, attempt: attempt, hint: nil, captureID: captureID)
        }

        recordsSubject.send(records)
    }

    func schedule(index: Int, attempt: Int, hint: TimeInterval?, captureID: UUID) {
        guard !backoff.isTerminal(afterAttempt: attempt) else {
            try? journal.append(.failed(captureID: captureID, at: clock.now))
            records[index].status = .failed
            records[index].nextAttemptAt = nil
            return
        }

        let due = clock.now.addingTimeInterval(
            backoff.delay(afterAttempt: attempt, retryAfter: hint)
        )
        try? journal.append(.retryScheduled(captureID: captureID,
                                            nextAttemptAt: due,
                                            at: clock.now))
        records[index].nextAttemptAt = due
    }
}
