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

        static let sharpness = Threshold(
            enter: Decimal(60) / Decimal(100),
            exit: Decimal(45) / Decimal(100)
        )

        static let meanLuma = Threshold(
            enter: Decimal(35) / Decimal(100),
            exit: Decimal(25) / Decimal(100)
        )

        static let clippedFraction = Threshold(
            enter: Decimal(5) / Decimal(100),
            exit: Decimal(10) / Decimal(100)
        )

        static let motion = Threshold(
            enter: Decimal(2) / Decimal(100),
            exit: Decimal(4) / Decimal(100)
        )
    }

    /// The parts of a step that must be present and readable for it to survive.
    private struct ValidatedCore {
        let id: String
        let kind: StepKind
        let roi: NormalizedRegion
        let thresholds: Thresholds
        let notes: [Diagnostic]
    }

    private enum GateResult {
        case passed(ValidatedCore)
        case discarded(Diagnostic)
    }

    static func validate(
        _ raw: RawStep,
        alreadySeen: Set<String>
    ) -> StepOutcome {
        var container = raw.container

        switch gate(
            &container,
            alreadySeen: alreadySeen
        ) {
        case .discarded(let diagnostic):
            return .skipped(diagnostic)

        case .passed(let core):
            return assemble(
                core,
                from: &container
            )
        }
    }

    /// Anything that fails here discards the step.
    private static func gate(
        _ container: inout LenientContainer,
        alreadySeen: Set<String>
    ) -> GateResult {
        guard let id = requiredStepID(from: &container) else {
            return .discarded(missingIDDiagnostic())
        }

        guard !alreadySeen.contains(id) else {
            return .discarded(duplicateIDDiagnostic(stepID: id))
        }

        guard let kind = stepKind(from: &container) else {
            return .discarded(unknownKindDiagnostic(stepID: id))
        }

        guard let roi = region(from: &container) else {
            return .discarded(invalidROIDiagnostic(stepID: id))
        }

        var notes: [Diagnostic] = []

        guard let thresholds = thresholds(
            from: &container,
            stepID: id,
            notes: &notes
        ) else {
            return .discarded(invalidThresholdDiagnostic(stepID: id))
        }

        return .passed(
            ValidatedCore(
                id: id,
                kind: kind,
                roi: roi,
                thresholds: thresholds,
                notes: notes
            )
        )
    }

    private static func requiredStepID(
        from container: inout LenientContainer
    ) -> String? {
        container.decodeIfPresent(
            String.self,
            "id"
        )
    }

    private static func stepKind(
        from container: inout LenientContainer
    ) -> StepKind? {
        guard let kindName = container.decodeIfPresent(
            String.self,
            "kind"
        ) else {
            return nil
        }

        return StepKind(rawValue: kindName)
    }

    private static func missingIDDiagnostic() -> Diagnostic {
        Diagnostic(
            severity: .warning,
            message: "step is missing its id"
        )
    }

    private static func duplicateIDDiagnostic(stepID: String) -> Diagnostic {
        Diagnostic(
            severity: .warning,
            stepID: stepID,
            message: "duplicate id, this occurrence was dropped"
        )
    }

    private static func unknownKindDiagnostic(stepID: String) -> Diagnostic {
        Diagnostic(
            severity: .warning,
            stepID: stepID,
            message: "unknown step kind, skipped rather than degraded"
        )
    }

    private static func invalidROIDiagnostic(stepID: String) -> Diagnostic {
        Diagnostic(
            severity: .warning,
            stepID: stepID,
            message: "missing or invalid roi, nothing to measure"
        )
    }

    private static func invalidThresholdDiagnostic(stepID: String) -> Diagnostic {
        Diagnostic(
            severity: .warning,
            stepID: stepID,
            message: "thresholds contain a present but invalid value"
        )
    }

    /// The step already survived; everything here only produces diagnostics.
    private static func assemble(
        _ core: ValidatedCore,
        from container: inout LenientContainer
    ) -> StepOutcome {
        var notes = core.notes

        let label = container.decodeIfPresent(
            String.self,
            "label"
        ) ?? core.id

        let holdFrames = holdFrames(
            from: &container,
            stepID: core.id,
            notes: &notes
        )

        for key in container.unusedKeys {
            notes.append(
                Diagnostic(
                    severity: .info,
                    stepID: core.id,
                    message: "unknown key '\(key)' ignored"
                )
            )
        }

        let step = Step(
            id: core.id,
            kind: core.kind,
            label: label,
            roi: core.roi,
            thresholds: core.thresholds,
            holdFrames: holdFrames
        )

        return .success(
            step,
            notes: notes
        )
    }

    private static func holdFrames(
        from container: inout LenientContainer,
        stepID: String,
        notes: inout [Diagnostic]
    ) -> Int {
        guard let (value, coerced) = Coercion.integer(
            &container,
            "holdFrames"
        ) else {
            notes.append(
                Diagnostic(
                    severity: .info,
                    stepID: stepID,
                    message: "holdFrames unreadable, default of "
                        + "\(Defaults.holdFrames) applied"
                )
            )

            return Defaults.holdFrames
        }

        if coerced {
            notes.append(
                Diagnostic(
                    severity: .info,
                    stepID: stepID,
                    message: "holdFrames arrived as a string and was coerced"
                )
            )
        }

        return value
    }

    static func region(
        from container: inout LenientContainer
    ) -> NormalizedRegion? {
        guard
            var roi = container.nested("roi"),
            let x = roi.decodeIfPresent(
                Double.self,
                "x"
            ),
            let y = roi.decodeIfPresent(
                Double.self,
                "y"
            ),
            let width = roi.decodeIfPresent(
                Double.self,
                "width"
            ),
            let height = roi.decodeIfPresent(
                Double.self,
                "height"
            )
        else {
            return nil
        }

        return NormalizedRegion(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }

    static func thresholds(
        from container: inout LenientContainer,
        stepID: String,
        notes: inout [Diagnostic]
    ) -> Thresholds? {
        guard var group = container.nested("thresholds") else {
            return nil
        }

        guard
            let sharpness = threshold(
                named: "sharpness",
                from: &group,
                defaultValue: Defaults.sharpness,
                stepID: stepID,
                notes: &notes
            ),
            let meanLuma = threshold(
                named: "meanLuma",
                from: &group,
                defaultValue: Defaults.meanLuma,
                stepID: stepID,
                notes: &notes
            ),
            let clippedFraction = threshold(
                named: "clippedFraction",
                from: &group,
                defaultValue: Defaults.clippedFraction,
                stepID: stepID,
                notes: &notes
            ),
            let motion = threshold(
                named: "motion",
                from: &group,
                defaultValue: Defaults.motion,
                stepID: stepID,
                notes: &notes
            )
        else {
            return nil
        }

        return Thresholds(
            sharpness: sharpness,
            meanLuma: meanLuma,
            clippedFraction: clippedFraction,
            motion: motion
        )
    }

    private static func threshold(
        named name: String,
        from group: inout LenientContainer,
        defaultValue: Threshold,
        stepID: String,
        notes: inout [Diagnostic]
    ) -> Threshold? {
        guard group.contains(name) else {
            notes.append(
                Diagnostic(
                    severity: .info,
                    stepID: stepID,
                    message: "\(name) threshold missing, documented default applied"
                )
            )

            return defaultValue
        }

        guard
            var pair = group.nested(name),
            let enter = Coercion.decimal(
                &pair,
                "enter"
            )
        else {
            return nil
        }

        let exit = Coercion.decimal(
            &pair,
            "exit"
        ) ?? enter

        return Threshold(
            enter: enter,
            exit: exit
        )
    }
}
