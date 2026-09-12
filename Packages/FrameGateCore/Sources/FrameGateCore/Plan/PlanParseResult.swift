//
//  PlanParseResult.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 11/09/26.
//

public enum PlanError: Error, Equatable, Sendable {
  case malformedJSON
  case missingSteps
  case noUsableSteps
}

public enum PlanParseResult: Sendable {
  case success(Plan, diagnostics: [Diagnostic])
  case failure(PlanError)
}
