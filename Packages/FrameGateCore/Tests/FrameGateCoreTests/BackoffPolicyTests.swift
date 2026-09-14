//
//  BackoffPolicyTests.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import XCTest
@testable import FrameGateCore

final class BackoffPolicyTests: XCTestCase {

  /// Jitter fixed at 1.0 so the curve itself can be asserted exactly.
  private func policy(base: TimeInterval = 2,
                      cap: TimeInterval = 60,
                      maxAttempts: Int = 5,
                      jitter: Double = 1.0) -> BackoffPolicy {
    BackoffPolicy(base: base, cap: cap, maxAttempts: maxAttempts, jitter: { jitter })
  }
}

// MARK: - Curve

extension BackoffPolicyTests {

  func testTheDelayDoublesWithEachFailure() {
    let backoff = policy()

    XCTAssertEqual(backoff.delay(afterAttempt: 1, retryAfter: nil), 2)
    XCTAssertEqual(backoff.delay(afterAttempt: 2, retryAfter: nil), 4)
    XCTAssertEqual(backoff.delay(afterAttempt: 3, retryAfter: nil), 8)
    XCTAssertEqual(backoff.delay(afterAttempt: 4, retryAfter: nil), 16)
    XCTAssertEqual(backoff.delay(afterAttempt: 5, retryAfter: nil), 32)
  }

  func testTheCapHoldsWhenTheCurveWouldRunAway() {
    let backoff = policy()

    // Five attempts never reach the cap in practice — the last wait is 32s.
    // Forcing a high attempt exercises the cap rather than leaving it untested.
    XCTAssertEqual(backoff.delay(afterAttempt: 6, retryAfter: nil), 60)
    XCTAssertEqual(backoff.delay(afterAttempt: 12, retryAfter: nil), 60,
                   "uncapped this would be over four hours")
  }

  func testTheFinalJitteredDelayNeverExceedsTheCap() {
    let low = policy(jitter: 0.5)
    let high = policy(jitter: 1.5)

    XCTAssertEqual(
      low.delay(
        afterAttempt: 12,
        retryAfter: nil
      ),
      60
    )

    XCTAssertEqual(
      high.delay(
        afterAttempt: 12,
        retryAfter: nil
      ),
      60
    )
  }

  func testJitterStillAppliesBeforeTheDelayReachesTheCap() {
    let low = policy(jitter: 0.5)
    let high = policy(jitter: 1.5)

    XCTAssertEqual(
      low.delay(
        afterAttempt: 2,
        retryAfter: nil
      ),
      2
    )

    XCTAssertEqual(
      high.delay(
        afterAttempt: 2,
        retryAfter: nil
      ),
      6
    )
  }

  func testJitterSpreadsRetriesAcrossAWindow() {
    let backoff = BackoffPolicy(base: 2, cap: 60, maxAttempts: 5)
    var seen: Set<TimeInterval> = []

    for _ in 0..<50 {
      let delay = backoff.delay(afterAttempt: 2, retryAfter: nil)
      XCTAssertGreaterThanOrEqual(delay, 2, "4s at jitter 0.5")
      XCTAssertLessThanOrEqual(delay, 6, "4s at jitter 1.5")
      seen.insert(delay)
    }

    XCTAssertGreaterThan(seen.count, 10,
                         "captures that failed together must not all return at once")
  }
}

// MARK: - Server hint

extension BackoffPolicyTests {

  func testAServerHintWinsOverTheCurve() {
    let backoff = policy()

    XCTAssertEqual(backoff.delay(afterAttempt: 1, retryAfter: 30), 30,
                   "the server knows when it will be ready; the curve guesses")
    XCTAssertEqual(backoff.delay(afterAttempt: 4, retryAfter: 1), 1,
                   "a hint shorter than the curve still wins")
  }

  func testAServerHintIsNotJittered() {
    let backoff = policy(jitter: 1.5)

    XCTAssertEqual(backoff.delay(afterAttempt: 1, retryAfter: 30), 30,
                   "an explicit instruction is followed, not nudged")
  }

  func testAServerHintIsStillCapped() {
    let backoff = policy()

    XCTAssertEqual(backoff.delay(afterAttempt: 1, retryAfter: 3600), 60,
                   "an hour-long hint would strand the queue")
  }
}

// MARK: - Terminal threshold

extension BackoffPolicyTests {

  func testAttemptsAreBoundedBeforeBecomingTerminal() {
    let backoff = policy(maxAttempts: 5)

    XCTAssertFalse(backoff.isTerminal(afterAttempt: 4))
    XCTAssertTrue(backoff.isTerminal(afterAttempt: 5),
                  "the fifth failure is the last automatic one")
    XCTAssertTrue(backoff.isTerminal(afterAttempt: 6))
  }

  func testFiveAttemptsCoverRoughlyAMinute() {
    let backoff = policy()
    let total = (1...5).reduce(0.0) { sum, attempt in
      sum + backoff.delay(afterAttempt: attempt, retryAfter: nil)
    }

    XCTAssertEqual(total, 62,
                   "a longer outage exhausts the automatic retries by design")
  }
}
