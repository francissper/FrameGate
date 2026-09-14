# FrameGate

FrameGate is an iOS 17+ SwiftUI assessment app with two screens: Capture and Queue. It replays deterministic frames on Simulator, measures a normalized ROI, arms the shutter after consecutive good frames, persists accepted captures, and drains them through a durable serial upload queue.

## Run

Built with Xcode 26.6 on macOS 26.4; deployment target is iOS 17+. Open `FrameGate.xcodeproj`, select the `FrameGate` scheme, and run on an iPhone Simulator. Xcode 16 compatibility is unverified.

The app uses `FakeTransport.suggestedScript` by default. The first capture follows `503, 503, timeout, 500, 201`; later captures succeed immediately.

To use the real HTTP transport, add under Product → Scheme → Edit Scheme → Run → Arguments:

```text
USE_REAL_UPLOAD=1
UPLOAD_ENDPOINT=http://localhost:8080/v1/captures
```

`UPLOAD_ENDPOINT` is optional.

Run tests and lint:

```bash
cd Packages/FrameGateCore
swift test
cd ../..
swiftlint --config .swiftlint.yml
```

Start the mock server with:

```bash
docker compose up --build
```

## Architecture and frame path

`FrameGateCore` contains parsing, replay, ROI mapping, luma analysis, gate logic, manifest encoding, persistence, transports, and queueing; SwiftUI screens contain no pixel math or queue/session references. Dependencies are injected through protocols.

`ROIMapper` is the single source of truth for both buffer and view rectangles across rotation, mirroring, display orientation, view size, and fill mode.

`LumaAnalyzer` reads the Y plane directly with `bytesPerRow`, correct lock/unlock pairing, reusable scratch storage, and off-main processing. Sharpness is mean absolute horizontal/vertical neighbour difference, normalized against the generated checkerboard baseline (`K = 26.67`). Exposure uses mean luma plus the worse clipped-pixel fraction. Motion is mean absolute difference against the previous 32×32 downsample. These formulas were chosen for deterministic, low-cost per-frame work.

## Plan parsing

Parsing is fail-soft per step and fail-hard only when the plan is unusable. The malformed fixture covers: mixed key casing → accepted case-insensitively; null/absent optional → treated equivalently; numeric string → coerced when unambiguous; unknown kind → step skipped; duplicate id → first wins; null ROI → step skipped; timezone-less timestamp → UTC; decimal that cannot be parsed without guessing → step skipped; unknown keys → ignored with diagnostics.

Defaults: missing metric threshold → documented per-metric default; missing `exit` → `enter`; missing `holdFrames` → `5`; missing `label` → step id. Present-but-invalid thresholds never silently default.

## Upload contract and durability

`POST /v1/captures` is multipart with `manifest` JSON and `frame` JPEG plus `Idempotency-Key`. The manifest uses ISO-8601 UTC timestamps with milliseconds, sensor rotation as degrees, display orientation as a label, ROI normalized to 0…1 from the top-left, and metrics encoded as four-decimal strings to avoid binary-float drift.

JPEG, manifest, and journal state are persisted before networking. Drain is serial; attempts are recorded before awaiting transport; retries reuse the same idempotency key; retryable failures use bounded exponential backoff with jitter/cap and `Retry-After`; permanent failure becomes `failed` with manual retry.

## Trade-offs, cuts, unverified

The demo uses `ReplayFrameSource`; real `AVCaptureSession` is intentionally not implemented because Simulator replay is the required path. Only the `single` step kind is implemented; burst capture, background upload, thumbnails, and extra screens are intentionally omitted. The queue has no explicit storage-capacity limit; production code should add storage-pressure and retention policies. The mock server verifies endpoint/idempotency behavior but not deep multipart contents. Physical-device behavior and Xcode 16 compatibility are unverified.
