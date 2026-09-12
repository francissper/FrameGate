//
//  Plan.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 11/09/26.
//

import Foundation

public struct Step: Equatable, Sendable {
  public let id: String
  public let kind: StepKind
  public let label: String
  public let roi: NormalizedRegion
  public let thresholds: Thresholds
  public let holdFrames: Int
  public init(id: String, kind: StepKind, label: String,
              roi: NormalizedRegion, thresholds: Thresholds, holdFrames: Int) {
    self.id = id
    self.kind = kind
    self.label = label
    self.roi = roi
    self.thresholds = thresholds
    self.holdFrames = holdFrames
  }
}

public struct Plan: Equatable, Sendable {
  public let id: String
  public let createdAt: Date
  public let steps: [Step]
  public init(id: String, createdAt: Date, steps: [Step]) {
    self.id = id
    self.createdAt = createdAt
    self.steps = steps
  }
}
