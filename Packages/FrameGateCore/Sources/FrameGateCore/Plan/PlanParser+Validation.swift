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

    static func validate(_ raw: RawStep, alreadySeen: Set<String>) -> StepOutcome {
        var container = raw.container
        var notes: [Diagnostic] = []

        // Gates: any failure here discards the step.

        guard let id = container.decodeIfPresent(String.self, "id") else {
            return .skipped(Diagnostic(
                severity: .warning,
                message: "step is missing its id"
            ))
        }

        guard !alreadySeen.contains(id) else {
            return .skipped(Diagnostic(
                severity: .warning,
                stepID: id,
                message: "duplicate id, this occurrence was dropped"
            ))
        }

        guard let kindName = container.decodeIfPresent(String.self, "kind"),
              let kind = StepKind(rawValue: kindName) else {
            return .skipped(Diagnostic(
                severity: .warning,
                stepID: id,
                message: "unknown step kind, skipped rather than degraded"
            ))
        }

        guard let roi = region(from: &container) else {
            return .skipped(Diagnostic(
                severity: .warning,
                stepID: id,
                message: "missing or invalid roi, nothing to measure"
            ))
        }

        guard let thresholds = thresholds(from: &container) else {
            return .skipped(Diagnostic(
                severity: .warning,
                stepID: id,
                message: "a threshold could not be read as a decimal"
            ))
        }

        // The step survives; from here on only diagnostics.

        let label = container.decodeIfPresent(String.self, "label") ?? id

        var holdFrames = Defaults.holdFrames
        if let (value, coerced) = Coercion.integer(&container, "holdFrames") {
            holdFrames = value
            if coerced {
                notes.append(Diagnostic(
                    severity: .info,
                    stepID: id,
                    message: "holdFrames arrived as a string and was coerced"
                ))
            }
        } else {
            notes.append(Diagnostic(
                severity: .info,
                stepID: id,
                message: "holdFrames unreadable, default of \(Defaults.holdFrames) applied"
            ))
        }

        for key in container.unusedKeys {
            notes.append(Diagnostic(
                severity: .info,
                stepID: id,
                message: "unknown key '\(key)' ignored"
            ))
        }

        let step = Step(id: id, kind: kind, label: label,
                        roi: roi, thresholds: thresholds, holdFrames: holdFrames)
        return .success(step, notes: notes)
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
