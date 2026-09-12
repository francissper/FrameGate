//
//  PlanParser+Validation.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import Foundation

extension PlanParser {

    enum StepOutcome {
        case success(Step, notes: [Diagnostic])
        case skipped(Diagnostic)
    }

    enum Defaults {
        static let holdFrames = 5
    }

    /// The parts of a step that must be present and readable for it to survive.
    private struct ValidatedCore {
        let id: String
        let kind: StepKind
        let roi: NormalizedRegion
        let thresholds: Thresholds
    }

    private enum GateResult {
        case passed(ValidatedCore)
        case discarded(Diagnostic)
    }

    static func validate(_ raw: RawStep, alreadySeen: Set<String>) -> StepOutcome {
        var container = raw.container

        switch gate(&container, alreadySeen: alreadySeen) {
        case .discarded(let diagnostic):
            return .skipped(diagnostic)
        case .passed(let core):
            return assemble(core, from: &container)
        }
    }

    /// Anything that fails here discards the step.
    private static func gate(_ container: inout LenientContainer,
                             alreadySeen: Set<String>) -> GateResult {
        guard let id = container.decodeIfPresent(String.self, "id") else {
            return .discarded(Diagnostic(
                severity: .warning,
                message: "step is missing its id"
            ))
        }

        guard !alreadySeen.contains(id) else {
            return .discarded(Diagnostic(
                severity: .warning,
                stepID: id,
                message: "duplicate id, this occurrence was dropped"
            ))
        }

        guard let kindName = container.decodeIfPresent(String.self, "kind"),
              let kind = StepKind(rawValue: kindName) else {
            return .discarded(Diagnostic(
                severity: .warning,
                stepID: id,
                message: "unknown step kind, skipped rather than degraded"
            ))
        }

        guard let roi = region(from: &container) else {
            return .discarded(Diagnostic(
                severity: .warning,
                stepID: id,
                message: "missing or invalid roi, nothing to measure"
            ))
        }

        guard let thresholds = thresholds(from: &container) else {
            return .discarded(Diagnostic(
                severity: .warning,
                stepID: id,
                message: "a threshold could not be read as a decimal"
            ))
        }

        return .passed(ValidatedCore(id: id, kind: kind, roi: roi, thresholds: thresholds))
    }

    /// The step already survived; everything here only produces diagnostics.
    private static func assemble(_ core: ValidatedCore,
                                 from container: inout LenientContainer) -> StepOutcome {
        var notes: [Diagnostic] = []
        let label = container.decodeIfPresent(String.self, "label") ?? core.id
        let holdFrames = holdFrames(from: &container, stepID: core.id, notes: &notes)

        for key in container.unusedKeys {
            notes.append(Diagnostic(
                severity: .info,
                stepID: core.id,
                message: "unknown key '\(key)' ignored"
            ))
        }

        let step = Step(id: core.id,
                        kind: core.kind,
                        label: label,
                        roi: core.roi,
                        thresholds: core.thresholds,
                        holdFrames: holdFrames)
        return .success(step, notes: notes)
    }

    private static func holdFrames(from container: inout LenientContainer,
                                   stepID: String,
                                   notes: inout [Diagnostic]) -> Int {
        guard let (value, coerced) = Coercion.integer(&container, "holdFrames") else {
            notes.append(Diagnostic(
                severity: .info,
                stepID: stepID,
                message: "holdFrames unreadable, default of \(Defaults.holdFrames) applied"
            ))
            return Defaults.holdFrames
        }

        if coerced {
            notes.append(Diagnostic(
                severity: .info,
                stepID: stepID,
                message: "holdFrames arrived as a string and was coerced"
            ))
        }
        return value
    }

    static func region(from container: inout LenientContainer) -> NormalizedRegion? {
        guard var roi = container.nested("roi"),
              let x = roi.decodeIfPresent(Double.self, "x"),
              let y = roi.decodeIfPresent(Double.self, "y"),
              let width = roi.decodeIfPresent(Double.self, "width"),
              let height = roi.decodeIfPresent(Double.self, "height")
        else { return nil }

        return NormalizedRegion(x: x, y: y, width: width, height: height)
    }

    static func thresholds(from container: inout LenientContainer) -> Thresholds? {
        guard var group = container.nested("thresholds") else { return nil }

        func read(_ name: String) -> Threshold? {
            guard var pair = group.nested(name),
                  let enter = Coercion.decimal(&pair, "enter") else { return nil }
            let exit = Coercion.decimal(&pair, "exit") ?? enter
            return Threshold(enter: enter, exit: exit)
        }

        guard let sharpness = read("sharpness"),
              let meanLuma = read("meanLuma"),
              let clipped = read("clippedFraction"),
              let motion = read("motion")
        else { return nil }

        return Thresholds(sharpness: sharpness, meanLuma: meanLuma,
                          clippedFraction: clipped, motion: motion)
    }
}
