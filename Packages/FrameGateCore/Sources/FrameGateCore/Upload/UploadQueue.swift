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
/// The actor protects queue state, while `isDraining` explicitly prevents
/// reentrant drain calls from overlapping across the transport await.
public actor UploadQueue {

  private let journal: Journal
  private let transport: UploadTransport
  private let backoff: BackoffPolicy
  private let clock: Clock
  private let storage: URL

  private var records: [CaptureRecord] = []
  private var isDraining = false

  nonisolated(unsafe) private let recordsSubject =
    CurrentValueSubject<[CaptureRecord], Never>([])

  public init(
    journal: Journal,
    transport: UploadTransport,
    backoff: BackoffPolicy = BackoffPolicy(),
    clock: Clock = SystemClock(),
    storage: URL
  ) {
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
  public func enqueue(
    manifest: Data,
    frame: Data,
    captureID: UUID
  ) throws {
    let frameFilename = "\(captureID.uuidString).jpg"
    let manifestFilename = "\(captureID.uuidString).json"

    let framePath = storage.appendingPathComponent(frameFilename)
    let manifestPath = storage.appendingPathComponent(manifestFilename)

    // Files first: a record pointing at a file that is not there would be
    // worse than no record at all.
    try frame.write(
      to: framePath,
      options: .atomic
    )

    try manifest.write(
      to: manifestPath,
      options: .atomic
    )

    try journal.append(
      .captured(
        captureID: captureID,
        manifestFilename: manifestFilename,
        frameFilename: frameFilename,
        at: clock.now
      )
    )

    records.append(
      CaptureRecord(
        captureID: captureID,
        manifestFilename: manifestFilename,
        frameFilename: frameFilename
      )
    )

    recordsSubject.send(records)
  }

  /// Sends whatever is due. One attempt per call, one record at a time.
  public func drainOnce() async {
    guard !isDraining else {
      return
    }

    isDraining = true

    defer {
      isDraining = false
    }

    guard let index = nextDueIndex() else {
      return
    }

    let record = records[index]
    let attempt = record.attempts + 1

    let manifestPath = storage
      .appendingPathComponent(record.manifestFilename)
      .path

    let framePath = storage
      .appendingPathComponent(record.frameFilename)
      .path

    guard
      let manifest = FileManager.default.contents(
        atPath: manifestPath
      ),
      let frame = FileManager.default.contents(
        atPath: framePath
      )
    else {
      return
    }

    // The attempted event is written before the await. If the process dies
    // during the request, the attempt is already counted and the record
    // stays pending — no recovery pass needed.
    try? journal.append(
      .attempted(
        captureID: record.captureID,
        attempt: attempt,
        at: clock.now
      )
    )

    records[index].attempts = attempt
    recordsSubject.send(records)

    let outcome = await transport.send(
      manifest: manifest,
      frame: frame,
      idempotencyKey: record.captureID
    )

    apply(
      outcome,
      toRecordWith: record.captureID,
      attempt: attempt
    )
  }

  /// Puts a failed record back in line with its attempts reset.
  public func retryManually(_ captureID: UUID) throws {
    guard
      let index = records.firstIndex(
        where: { $0.captureID == captureID }
      ),
      records[index].status == .failed
    else {
      return
    }

    try journal.append(
      .manuallyRetried(
        captureID: captureID,
        at: clock.now
      )
    )

    records[index].status = .pending
    records[index].attempts = 0
    records[index].nextAttemptAt = nil

    recordsSubject.send(records)
  }

  public var currentRecords: [CaptureRecord] {
    records
  }
}

// MARK: - Private helpers

private extension UploadQueue {

  /// Returns the first record whose backoff has elapsed.
  ///
  /// A record that is still waiting does not block records behind it.
  func nextDueIndex() -> Int? {
    records.firstIndex { record in
      guard record.status == .pending else {
        return false
      }

      guard let due = record.nextAttemptAt else {
        return true
      }

      return due <= clock.now
    }
  }

  func apply(
    _ outcome: UploadOutcome,
    toRecordWith captureID: UUID,
    attempt: Int
  ) {
    guard let index = records.firstIndex(
      where: { $0.captureID == captureID }
    ) else {
      return
    }

    switch outcome {
    case .stored:
      // A duplicate flag means the server already had this key. The work is
      // complete either way, so both outcomes settle identically.
      try? journal.append(
        .uploaded(
          captureID: captureID,
          at: clock.now
        )
      )

      records[index].status = .uploaded
      records[index].nextAttemptAt = nil

    case .rejected:
      // A 422 does not receive the remaining attempts because retrying the
      // same invalid payload would fail in the same way.
      try? journal.append(
        .failed(
          captureID: captureID,
          at: clock.now
        )
      )

      records[index].status = .failed
      records[index].nextAttemptAt = nil

    case .retryable(let hint):
      schedule(
        index: index,
        attempt: attempt,
        hint: hint,
        captureID: captureID
      )

    case .timedOut:
      // A timeout is retryable, but the server may already have stored the
      // shot. Reusing the same idempotency key makes the retry safe.
      schedule(
        index: index,
        attempt: attempt,
        hint: nil,
        captureID: captureID
      )
    }

    recordsSubject.send(records)
  }

  func schedule(
    index: Int,
    attempt: Int,
    hint: TimeInterval?,
    captureID: UUID
  ) {
    guard !backoff.isTerminal(afterAttempt: attempt) else {
      try? journal.append(
        .failed(
          captureID: captureID,
          at: clock.now
        )
      )

      records[index].status = .failed
      records[index].nextAttemptAt = nil
      return
    }

    let due = clock.now.addingTimeInterval(
      backoff.delay(
        afterAttempt: attempt,
        retryAfter: hint
      )
    )

    try? journal.append(
      .retryScheduled(
        captureID: captureID,
        nextAttemptAt: due,
        at: clock.now
      )
    )

    records[index].nextAttemptAt = due
  }
}
