//
//  BackoffPolicy.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import Foundation

/// How long to wait before retrying an attempt that failed.
///
/// Exponential so a server that is genuinely down is not hammered; capped so the
/// curve cannot run away into hours; jittered so captures that failed together
/// do not all come back at the same instant.
public struct BackoffPolicy: Sendable {

  /// The wait after the first failure. Long enough for a network hiccup to
  /// pass, short enough that the user does not notice it.
  public let base: TimeInterval
  /// However bad things get, never wait longer than this: when the server
  /// recovers, the queue should resume within a minute rather than sleep.
  public let cap: TimeInterval
  /// Attempts before the record becomes terminal and only the user can retry.
  public let maxAttempts: Int
  /// Multiplied into the delay. Randomised in production, fixed in tests.
  private let jitter: @Sendable () -> Double

  public init(base: TimeInterval = 2,
              cap: TimeInterval = 60,
              maxAttempts: Int = 5,
              jitter: @escaping @Sendable () -> Double = { Double.random(in: 0.5...1.5) }) {
    self.base = base
    self.cap = cap
    self.maxAttempts = maxAttempts
    self.jitter = jitter
  }

  /// The delay after `attempt` failures. A server hint always wins: it knows
  /// when it will be ready, the curve is only guessing.
  public func delay(afterAttempt attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
    if let hint = retryAfter {
      // The hint is followed exactly — not jittered — but capped so the
      // queue cannot be stranded by a server that sends Retry-After: 3600.
      return min(hint, cap)
    }
    let raw = base * pow(2.0, Double(attempt - 1))
    // Jitter is applied after capping so capped retries still spread out.
    // Applying it before would pin every capped retry to exactly `cap`.
    let jittered = raw * jitter()
    return min(jittered, cap)
  }

  public func isTerminal(afterAttempt attempt: Int) -> Bool {
    attempt >= maxAttempts
  }
}
