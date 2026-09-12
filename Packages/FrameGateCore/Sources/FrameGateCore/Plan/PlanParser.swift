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
        guard let root = try? JSONDecoder().decode(RawPlan.self, from: data) else {
            return .failure(.malformedJSON)
        }
        guard let rawSteps = root.steps else {
            return .failure(.missingSteps)
        }

        var diagnostics: [Diagnostic] = []
        let createdAt = Self.date(from: root.createdAt, into: &diagnostics)

        var steps: [Step] = []
        var seenIDs: Set<String> = []

        for raw in rawSteps {
            switch Self.validate(raw, alreadySeen: seenIDs) {
            case .success(let step, let notes):
                seenIDs.insert(step.id)
                steps.append(step)
                diagnostics.append(contentsOf: notes)
            case .skipped(let note):
                diagnostics.append(note)
            }
        }

        guard !steps.isEmpty else { return .failure(.noUsableSteps) }

        let plan = Plan(id: root.planId ?? "unnamed-plan", createdAt: createdAt, steps: steps)
        return .success(plan, diagnostics: diagnostics)
    }
}
