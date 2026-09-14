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
  private var drainTimer: Timer?

  init() {
    let loaded = Self.loadPlan()
    plan = loaded.plan

    let size = CGSize(width: 1280, height: 720)
    let patterns: [PatternGenerator.Pattern] = [.sharp, .sharp, .sharp, .sharpLeftHalf]
    let buffers = patterns.compactMap { PatternGenerator.makeBuffer($0, size: size) }
    let source = ReplayFrameSource(buffers: buffers, frameRate: 60)
    pipeline = CapturePipeline(source: source, plan: plan)

    storageDirectory = FileManager.default.urls(for: .documentDirectory,
                                                in: .userDomainMask)[0]
    let journalURL = storageDirectory.appendingPathComponent("queue.log")

    // Points at the mock server, started with the documented docker command.
    // Retry and backoff are still graded against the fake transport in tests.
    let endpoint = Self.uploadEndpoint()
    let transport = URLSessionUploadTransport(endpoint: endpoint)

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

  func startDraining() {
    drainTimer?.invalidate()
    drainTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { await self?.queue.drainOnce() }
    }
  }

  func stopDraining() {
    drainTimer?.invalidate()
    drainTimer = nil
  }

  /// Builds the manifest and durably enqueues the accepted capture.
  ///
  /// Returns `true` only after both payloads have been persisted by the queue.
  func enqueue(_ shot: CapturedShot) async -> Bool {
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

    do {
      let manifestData = try ManifestEncoder.encode(manifest)

      try await queue.enqueue(
        manifest: manifestData,
        frame: shot.frameData,
        captureID: manifest.captureID
      )

      return true
    } catch {
      print("Failed to enqueue capture: \(error)")
      return false
    }
  }
}

// MARK: - Plan loading

private extension AppContainer {

  /// Defaults to the mock server on localhost; overridable so a different
  /// build or a CI run can point elsewhere without recompiling.
  static func uploadEndpoint() -> URL {
    if let override = ProcessInfo.processInfo.environment["UPLOAD_ENDPOINT"],
       let url = URL(string: override) {
      return url
    }

    guard let url = URL(string: "http://localhost:8080/v1/captures") else {
      preconditionFailure("Invalid default upload endpoint")
    }
    return url
  }

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
