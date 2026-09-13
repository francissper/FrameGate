//
//  JournalTests.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import XCTest
@testable import FrameGateCore

final class JournalTests: XCTestCase {

  private var directory: URL!
  private var journalURL: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory,
                                            withIntermediateDirectories: true)
    journalURL = directory.appendingPathComponent("queue.log")
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func makeJournal() throws -> Journal {
    try Journal(url: journalURL)
  }

  private func uuid(_ suffix: String) throws -> UUID {
    try XCTUnwrap(UUID(uuidString: "7F3E2A1C-0000-4000-8000-\(suffix)"))
  }

  private func captured(_ id: UUID, at seconds: TimeInterval = 0) -> JournalEvent {
    .captured(captureID: id,
              manifestPath: "\(id.uuidString).json",
              framePath: "\(id.uuidString).jpg",
              at: Date(timeIntervalSince1970: seconds))
  }
}

// MARK: - Replay

extension JournalTests {

  func testACapturedEventBecomesAPendingRecord() throws {
    let firstID = try uuid("000000000001")
    let journal = try makeJournal()
    try journal.append(captured(firstID))

    let records = try journal.replay()

    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records[0].captureID, firstID)
    XCTAssertEqual(records[0].status, .pending)
    XCTAssertEqual(records[0].attempts, 0)
  }

  func testOrderIsPreservedAcrossCaptures() throws {
    let firstID = try uuid("000000000001")
    let secondID = try uuid("000000000002")
    let journal = try makeJournal()
    try journal.append(captured(firstID, at: 10))
    try journal.append(captured(secondID, at: 20))

    XCTAssertEqual(try journal.replay().map(\.captureID), [firstID, secondID])
  }

  func testAttemptsAccumulate() throws {
    let firstID = try uuid("000000000001")
    let journal = try makeJournal()
    try journal.append(captured(firstID))
    try journal.append(.attempted(captureID: firstID, attempt: 1,
                                  at: Date(timeIntervalSince1970: 1)))
    try journal.append(.attempted(captureID: firstID, attempt: 2,
                                  at: Date(timeIntervalSince1970: 3)))

    XCTAssertEqual(try journal.replay()[0].attempts, 2)
  }

  func testALaterEventSupersedesAnEarlierOne() throws {
    let firstID = try uuid("000000000001")
    let journal = try makeJournal()
    try journal.append(captured(firstID))
    try journal.append(.attempted(captureID: firstID, attempt: 1,
                                  at: Date(timeIntervalSince1970: 1)))
    try journal.append(.uploaded(captureID: firstID,
                                 at: Date(timeIntervalSince1970: 2)))

    let record = try journal.replay()[0]
    XCTAssertEqual(record.status, .uploaded)
    XCTAssertNil(record.nextAttemptAt, "an uploaded record is not scheduled")
  }

  func testARetryScheduleSurvivesReplay() throws {
    let firstID = try uuid("000000000001")
    let journal = try makeJournal()
    let next = Date(timeIntervalSince1970: 120)

    try journal.append(captured(firstID))
    try journal.append(.attempted(captureID: firstID, attempt: 1,
                                  at: Date(timeIntervalSince1970: 1)))
    try journal.append(.retryScheduled(captureID: firstID, nextAttemptAt: next,
                                       at: Date(timeIntervalSince1970: 1)))

    let record = try journal.replay()[0]
    XCTAssertEqual(record.status, .pending)
    XCTAssertEqual(record.nextAttemptAt, next)
  }
}

// MARK: - Durability

extension JournalTests {

  func testAnEventIsOnDiskBeforeAppendReturns() throws {
    let firstID = try uuid("000000000001")
    let journal = try makeJournal()
    try journal.append(captured(firstID))

    // Read the file directly: no flush, no close, no cooperation from the
    // journal object. If the bytes are not there, the promise is broken.
    let raw = try String(contentsOf: journalURL, encoding: .utf8)
    XCTAssertTrue(raw.contains(firstID.uuidString))
  }

  func testASecondJournalSeesWhatTheFirstWrote() throws {
    let firstID = try uuid("000000000001")
    let first = try makeJournal()
    try first.append(captured(firstID))

    // Standing in for relaunch after a force-quit: a new instance over the
    // same file, with nothing handed over in memory.
    let second = try makeJournal()

    XCTAssertEqual(try second.replay().map(\.captureID), [firstID])
  }

  func testAnInterruptedFinalLineIsDiscardedAndTheRestSurvives() throws {
    let firstID = try uuid("000000000001")
    let secondID = try uuid("000000000002")
    let journal = try makeJournal()
    try journal.append(captured(firstID))
    try journal.append(captured(secondID, at: 10))

    // Simulate the process dying mid-write: truncate the last line.
    var raw = try String(contentsOf: journalURL, encoding: .utf8)
    raw = String(raw.dropLast(20))
    try raw.write(to: journalURL, atomically: true, encoding: .utf8)

    let records = try Journal(url: journalURL).replay()

    XCTAssertEqual(records.map(\.captureID), [firstID],
                   "the torn line goes, everything before it stays")
  }

  func testAnUnknownEventTypeIsSkippedRatherThanFatal() throws {
    let firstID = try uuid("000000000001")
    let secondID = try uuid("000000000002")
    let journal = try makeJournal()
    try journal.append(captured(firstID))

    var raw = try String(contentsOf: journalURL, encoding: .utf8)
    raw += "{\"event\":\"somethingNewer\",\"id\":\"\(secondID.uuidString)\"}\n"
    try raw.write(to: journalURL, atomically: true, encoding: .utf8)

    XCTAssertEqual(try Journal(url: journalURL).replay().map(\.captureID), [firstID])
  }

  func testAnEmptyJournalReplaysToNothing() throws {
    XCTAssertTrue(try makeJournal().replay().isEmpty)
  }
}

// MARK: - In-flight state

extension JournalTests {

  func testThereIsNoInFlightStateToRecoverFrom() throws {
    let firstID = try uuid("000000000001")
    let journal = try makeJournal()
    try journal.append(captured(firstID))
    try journal.append(.attempted(captureID: firstID, attempt: 1,
                                  at: Date(timeIntervalSince1970: 1)))

    // The process dies here: the POST went out, no response came back.
    let afterRelaunch = try Journal(url: journalURL).replay()[0]

    XCTAssertEqual(afterRelaunch.status, .pending,
                   "an attempt with no outcome leaves the record pending - "
                   + "nothing is stuck, and no recovery pass is needed")
    XCTAssertEqual(afterRelaunch.attempts, 1)
  }
}
