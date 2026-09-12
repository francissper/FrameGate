//
//  PlanParser.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 11/09/26.
//

import Foundation

public struct PlanParser {
  public init() {}
  public func parse(_ data: Data) -> PlanParseResult {
    .failure(.malformedJSON)
  }
}
