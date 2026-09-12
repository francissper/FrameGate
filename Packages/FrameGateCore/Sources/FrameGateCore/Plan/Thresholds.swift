//
//  Thresholds.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 11/09/26.
//

import Foundation

public struct Threshold: Equatable, Sendable {
  /// Value a metric must cross to flip the verdict to passing.
  public let enter: Decimal
  /// Value a metric must fall past to flip back to failing.
  public let exit: Decimal
  public init(enter: Decimal, exit: Decimal) {
    self.enter = enter
    self.exit = exit
  }
}

public struct Thresholds: Equatable, Sendable {
  public let sharpness: Threshold
  public let meanLuma: Threshold
  public let clippedFraction: Threshold
  public let motion: Threshold
  public init(sharpness: Threshold, meanLuma: Threshold, clippedFraction: Threshold, motion: Threshold) {
    self.sharpness = sharpness
    self.meanLuma = meanLuma
    self.clippedFraction = clippedFraction
    self.motion = motion
  }
}
