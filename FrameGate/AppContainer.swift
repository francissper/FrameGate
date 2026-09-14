//
//  AppContainer.swift
//  FrameGate
//
//  Created by Franciss Peralta on 13/09/26.
//

import Foundation
import FrameGateCore
import Combine


/// The composition root. One instance, created once, handed to both screens.
/// Nothing here is a singleton — it is built by hand and passed down, which is
/// the dependency injection the brief asks for.
@MainActor
final class AppContainer: ObservableObject {

    let plan: Plan
    let pipeline: CapturePipeline
    let queue: UploadQueue

    private let storageDirectory: URL

    init() {
        let loaded = Self.loadPlan()
        plan = loaded.plan

        let size = CGSize(width: 160, height: 120)
        let patterns: [PatternGenerator.Pattern] = [.sharp, .sharp, .sharp, .sharpLeftHalf]
        let buffers = patterns.compactMap { PatternGenerator.makeBuffer($0, size: size) }
        let source = ReplayFrameSource(buffers: buffers, frameRate: 60)
        pipeline = CapturePipeline(source: source, plan: plan)

        storageDirectory = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask)[0]
        let journalURL = storageDirectory.appendingPathComponent("queue.log")

        // A real transport would wrap URLSession and point at the mock server.
        // Until that lands, the fake keeps the app runnable end to end.
        let transport = FakeTransport(script: [], thereafter: .stored(duplicate: false))

        do {
            let journal = try Journal(url: journalURL)
            queue = UploadQueue(journal: journal, transport: transport, storage: storageDirectory)
        } catch {
            preconditionFailure("Could not open the queue journal: \(error)")
        }
    }

    func restoreQueue() async {
        try? await queue.restore()
    }

    /// Encodes the shot, builds its manifest, and enqueues both. Called from
    /// the capture screen's one-shot effect — never from the frame path.
    func enqueue(_ shot: CapturedShot) async {
        guard let frameData = JPEGEncoder.encode(shot.buffer) else { return }

        let manifest = CaptureManifest(
            captureID: UUID(),
            planID: plan.id,
            planCreatedAt: plan.createdAt,
            stepID: shot.step.id,
            capturedAt: Date(),
            sensorRotation: shot.sensorRotation,
            displayOrientation: shot.displayOrientation,
            mirrored: shot.mirrored,
            region: shot.step.roi,
            metrics: shot.metrics,
            holdFramesRequired: shot.step.holdFrames,
            framesDropped: shot.framesDropped
        )

        guard let manifestData = try? ManifestEncoder.encode(manifest) else { return }

        try? await queue.enqueue(manifest: manifestData,
                                 frame: frameData,
                                 captureID: manifest.captureID)
    }
}

// MARK: - Plan loading

private extension AppContainer {

    struct LoadedPlan {
        let plan: Plan
        let diagnostics: [Diagnostic]
    }

    /// Loads the bundled plan through the same tolerant parser the tests cover.
    /// Diagnostics are logged as plain text — the brief asks for no error UI.
    static func loadPlan() -> LoadedPlan {
        guard let url = Bundle.main.url(forResource: "plan", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            preconditionFailure("plan.json is missing from the app bundle")
        }

        switch PlanParser().parse(data) {
        case .success(let plan, let diagnostics):
            for diagnostic in diagnostics {
                print(diagnostic.text)
            }
            return LoadedPlan(plan: plan, diagnostics: diagnostics)

        case .failure(let error):
            preconditionFailure("plan.json failed to parse: \(error)")
        }
    }
}
