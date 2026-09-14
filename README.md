# FrameGate

## Running it

Built with Xcode 26.6 on macOS 26.4 (Apple M5), swift-tools-version 6.0,
deployment target iOS 17.0. Xcode 16 cannot be installed on macOS 26, so
compatibility with that version is unverified.

SwiftLint runs as a build phase with `force_unwrapping` set to error. If SwiftLint
is not installed (`brew install swiftlint`), the phase logs a warning and the build
continues.

### The app

Select the `FrameGate` scheme and run on any iPhone Simulator. There is no
camera dependency: `ReplayFrameSource` plays back generated patterns, so the
app runs end to end with no physical device.

On launch the bundled `plan.json` loads through the same tolerant parser the
Core tests cover; any diagnostic is printed to the console rather than shown
in the UI, as the brief asks. Firing the shutter while `armed` encodes the
frame to JPEG, builds its manifest, and enqueues both — watch the counter next
to "Queue" in the header rise, then open Queue to see the record move from
`pending` through its retry schedule to `uploaded`.

### The tests

Select the `FrameGateCoreTests` scheme and run ⌘U. All logic lives in the
`FrameGateCore` package, so the tests run without launching the app.

### The mock server

```bash
cd mock-server
docker build -t framegate-mock .
docker run -p 8080:8080 framegate-mock
```

The app points at `http://localhost:8080/v1/captures` via
`URLSessionUploadTransport`. On the Simulator, `localhost` resolves to the host
Mac, so no extra networking setup is needed. To point at a different endpoint
without recompiling, set `UPLOAD_ENDPOINT` in Xcode under Product -> Scheme ->
Edit Scheme -> Run -> Arguments -> Environment Variables.

The first idempotency key exercises the brief's suggested script — 503, 503,
timeout, 500, 201 — and settles as `uploaded`; every key after that succeeds on
the first attempt. Retry and backoff timing are graded against `FakeTransport`
in the test suite, not against this server.

## Plan format

The plan is bundled with the app and loaded at launch. It is an ordered list of
shots; each step names the region to measure, the thresholds each metric must
meet, and how many consecutive good frames arm the shutter.

```json
{
  "planId": "warehouse-intake-v1",
  "createdAt": "2026-09-12T04:30:00Z",
  "steps": [
    {
      "id": "front-label",
      "kind": "single",
      "label": "Front label",
      "roi": { "x": 0.15, "y": 0.30, "width": 0.70, "height": 0.25 },
      "thresholds": {
        "sharpness": { "enter": "0.60", "exit": "0.45" },
        "meanLuma": { "enter": "0.35", "exit": "0.25" },
        "clippedFraction": { "enter": "0.05", "exit": "0.10" },
        "motion": { "enter": "0.02", "exit": "0.04" }
      },
      "holdFrames": 8
    }
  ]
}
```

### Field decisions

**`roi`** is normalized to 0…1 so one plan works across devices and preview
sizes. The origin is top-left, matching both UIKit and the row order of a
`CVPixelBuffer`, so the mapper never inverts the incoming rectangle — it only
does so when rotation demands it. `width`/`height` rather than `right`/`bottom`
makes a degenerate rectangle obvious.

**`thresholds`** carries `enter` and `exit` per metric, which is the hysteresis
band. A verdict flips to passing only above `enter` and back to failing only
below `exit`; between them it holds. Without that band a metric hovering on the
threshold flips the verdict every frame and the shutter chatters.

Direction differs per metric: for `sharpness` and `meanLuma` higher is better,
so `enter > exit`. For `clippedFraction` and `motion` lower is better, so
`enter < exit`.

Exposure is split into `meanLuma` and `clippedFraction` because a frame can be
well exposed on average while blowing out a region. Separate thresholds also
let the HUD name which half is blocking.

**Threshold values are strings** and are decoded with `Decimal(string:)`, never
through `Double`. Binary floating point cannot represent decimal fractions
exactly, and these values are compared against metrics on every frame. Sending
them as JSON numbers would let `JSONDecoder` produce a `Double` first, losing
precision before any conversion. The domain model stores them as `Decimal`.

**`holdFrames`** carries its unit in the name. The hold is counted in frames,
never on a timer: if frames were dropped, a timer would still elapse and arm the
shutter on evidence that was never gathered.

**`kind`** currently accepts only `single`. It exists so the format can grow a
second step type without a schema change.

**`createdAt`** is plan-level metadata and travels into the upload manifest so a
capture can be traced back to the plan version that produced it.

### Fail-soft and fail-hard

The whole plan fails in three cases: the file is not valid JSON, the `steps` key
is missing, or no step survives validation. Everything else is fail-soft — the
plan loads with its usable steps and every problem is reported as a non-fatal
diagnostic.

### Parser behaviour per malformation

The guiding rule: be tolerant when the author's intent is unambiguous, be strict
when guessing could capture the wrong shot.

| Malformation | Behaviour |
| --- | --- |
| Mixed key casing | Keys are matched case-insensitively; the step is kept. If two keys normalise to the same name, the first wins and a warning is emitted |
| Nullable sometimes absent | Absent and `null` are equivalent; `label` falls back to `id` |
| Number sent as a string | Coerced when unambiguous (`"8"` → 8), with an info diagnostic. A value that does not convert invalidates the step |
| Unknown step kind | Step skipped, warning. Degrading to `single` would silently capture something other than what was asked for |
| Duplicate step id | First occurrence wins, the second is dropped with a warning |
| Declared object that is null | `roi: null` invalidates the step. Without a region there is nothing to measure |
| Timestamp with no timezone | Assumed UTC, info diagnostic. Assuming device-local time would make the same file mean different things in different places |
| Decimal that must not become a Double | Step skipped, no silent default. A default is for a *missing* threshold; a present-but-invalid one is an authoring error and masking it would run the step on criteria nobody set |
| Unknown keys | Ignored so the format can grow, but reported as an info diagnostic so a newer plan version is not silently half-read |

`plan_malformed.json` carries all nine malformations plus a partial threshold.
Steps 1–3 survive, steps 4–7 are skipped; the table above says why for each.

### Applied defaults

| Situation | Default |
| --- | --- |
| An entire threshold is missing | The documented per-metric default (values calibrated against the generated patterns) |
| Only `exit` is missing | `exit = enter`, i.e. no hysteresis band for that metric |
| `holdFrames` is missing | 5 |
| `label` is missing | Falls back to `id` |

## Frame source

The Simulator has no camera, so `ReplayFrameSource` plays back a pre-built
sequence of buffers at a fixed rate. A real `AVCaptureSession` would sit behind
the same `FrameSource` protocol without anything downstream changing.

Patterns are generated rather than bundled so the test data is readable in the
source: exactly where the sharp edge sits, exactly how dark the dark frame is.
Each one isolates a single metric — the checkerboard is sharp and well exposed,
the ramp fails sharpness alone, the flat dark field fails exposure, and the
half-sharp frame flips its verdict depending on which side of the midline the
ROI falls. The checker uses 16 and 235, the video-range limits, so the reference
frame is maximally sharp without registering as clipped.

Backpressure is a single slot behind an `os_unfair_lock`, not a buffered
publisher. When the consumer falls behind, the newest frame overwrites the slot
and the previous one is counted as dropped: there is no queue to grow, so
latency never accumulates. The drop count is published separately because the
HUD needs it as evidence that the backpressure is real — a buffered operator
would discard silently and leave nothing to show.

## ROI mapping

The plan's region is normalized against the **sensor buffer**, not the view. A
plan describes which part of the subject to photograph — "the label sits in the
upper third of the box" — so rotating the device must keep measuring the same
part of the subject even though the outline moves on screen. Normalizing against
the view would do the opposite: the outline would stay put and the measured
region would change with every rotation.

One pure function maps that region into both spaces:

```swift
func map(
    _ region: NormalizedRegion,
    bufferSize: CGSize,
    sensorRotation: Rotation,
    mirrored: Bool,
    displayOrientation: DisplayOrientation,
    viewSize: CGSize,
    fillMode: FillMode
) -> MappedRegion
```

`MappedRegion` carries the rectangle in buffer coordinates, used for measuring,
and in view coordinates, used for drawing. The on-screen outline is drawn only
from the latter — there is no hand-tuned offset anywhere, because the two
rectangles must describe the same region for any of the measurements to mean
anything.

`DisplayOrientation` is defined in Core rather than reusing
`UIInterfaceOrientation`, so the package never imports UIKit. The app maps from
UIKit to it at the boundary.

Because the region is normalized to the sensor, the buffer rectangle is
unaffected by rotation and mirroring — the same part of the subject is measured
either way. Only the view rectangle turns, which is what the outline on screen
follows: a wide band across the top of the frame is drawn as a horizontal strip
in portrait and a vertical one in landscape, while measuring identical pixels.

With `aspectFill` the content overflows the view, so a region near an edge can
legitimately be drawn partly outside it. `aspectFit` fits the whole frame inside
the view with letterboxing, so the outline is always fully visible.

The mapping signature takes seven inputs rather than folding them into a struct:
the brief names these exact parameters, and grouping them would hide what the
mapping actually depends on.

## Metrics

Measured inside the mapped region only, reading the Y plane directly with the
lock held for exactly the duration of the read. No `UIImage`, `CGImage` or Core
Image anywhere on this path, and no RGB conversion — a camera pipeline works in
YUV, and converting to measure a gradient would be throwing cycles away.

### Sharpness

Mean absolute difference between neighbouring pixels, measured both
horizontally and vertically:

    Σ|I(x+1,y) − I(x,y)| + Σ|I(x,y+1) − I(x,y)|

Chosen over the Laplacian variance or Tenengrad because it is the cheapest
operator that separates the test patterns, and this runs thirty times a second.
The Laplacian needs five reads per pixel and Sobel six; this needs three. Both
directions are measured so an image with purely vertical or purely horizontal
edges is not misread as flat. Sobel's advantage is noise robustness, which
synthetic patterns do not need.

Sharpness is the one metric that does not subsample: it measures adjacent
pixels, so skipping every other one would compare neighbours that are not
neighbours. Exposure and motion do subsample, since a mean and a downsample lose
nothing by it.

### Exposure

Mean luma over 0…1, plus two clipping fractions rather than one: pixels at or
below 5 have lost shadow detail, pixels at or above 250 have lost highlight
detail. Splitting them lets the HUD say which half is blocking instead of the
unhelpful "exposure". The plan carries a single `clippedFraction` threshold and
the worse of the two is what it compares against.

### Motion

Mean absolute difference against the previous frame's downsampled luma. The
downsample is a fixed 32×32 regardless of ROI size: fixed so the scratch buffer
never reallocates when the plan advances to a step with a different region, and
small enough that it acts as a low-pass filter, suppressing sensor noise so only
real movement registers.

The first frame has no predecessor and reports motion of 1.0 rather than 0.
Being pessimistic means the gate never arms on a frame it could not compare.
The same applies after `reset()`, called when the region changes: comparing
against a downsample of a different region would be meaningless.

### Sharpness baseline

Sharpness is scale-dependent, so a raw value carries no meaning on its own: it
changes with the subsampling factor and the size of the region. The raw figure
is divided by K, measured once on the reference checkerboard, so 1.0 means "as
sharp as the reference frame". K is a measured value recorded here, not a
constant picked blind.

Normalizing against the ROI's own local contrast instead would let a
low-contrast scene read fairly, but costs a second pass over the pixels and
makes plan thresholds depend on what is in front of the camera. With synthetic
patterns of known contrast, the fixed baseline is the better trade.

K = 26.67, measured on the reference checkerboard at 320×240. A checker of 16
and 235 in 8-pixel squares crosses an edge on roughly one pair of neighbours in
eight, putting the theoretical value near 219/8 = 27.4; the measured figure sits
slightly below because the region's last row and column have no neighbour to
compare against.

## Gate

One pure function from state, metrics, thresholds and a tick to a new state. The
tick is passed in rather than read from a clock inside, so a test can drive the
gate frame by frame with no waiting and no ambiguity about when a transition
happened.

### States

`blocked` carries the set of failing metrics — a set rather than one reason,
because several can fail at once and the HUD picks which to name. It is never
empty: with nothing failing the phase is `holding` or `armed` instead.
`holding` carries the run so far and what it needs. `armed` is the only phase in
which the shutter is enabled. `fired` is transient: the following frame moves to
the next step, or completes the plan if there is none.

### Smoothing and hysteresis

Each metric carries two thresholds and its verdict is held between frames. A
verdict flips to passing only once the value crosses `enter`, and back to
failing only once it crosses `exit`; between them it keeps whatever it had.
Without that band a value hovering on a single threshold flips the verdict every
frame, the run never accumulates, and the shutter chatters.

The band is asymmetric by design, and two cases in `gate_sequences.json` prove
it: the same mid-band value keeps a passing verdict if it was already passing,
and cannot start a run if it was not.

Direction differs per metric. Sharpness and mean luma pass by rising; clipping
and motion pass by falling, so their bands run the other way.

### The hold counter

Counted in frames, never on a timer, and reset to zero — not decremented — by
any failing frame. A timer would elapse regardless of how many frames actually
arrived, arming the shutter on evidence that was never gathered.

A new step starts from `unmeasured`: its region is different, so the previous
step's verdicts say nothing about it. This mirrors `LumaAnalyzer.reset()`, which
discards the previous downsample for the same reason.

## Upload queue

### Manifest

Field names, units and encodings are documented in `ManifestEncoder` and pinned
by `ManifestEncoderTests`: a field added or renamed fails the test before it
reaches the wire. Timestamps are ISO 8601 in UTC with milliseconds. Sensor
rotation is an angle so it travels as a number; display orientation is a label
so it travels as a string. The region uses the same 0…1 top-left convention as
the plan. Every measured value carries exactly four decimal places as a string,
so a receiving parser cannot turn 0.8412 into 0.8411999999999999.

The journal encodes its timestamps as epoch seconds rather than ISO 8601. It is
internal and only this code reads it; the manifest is a contract with a server
and gets the readable, unambiguous form.

### Durability semantics

The order on fire is: JPEG to disk, manifest to disk, `captured` to the journal,
and only then the network. Once `enqueue` returns, the capture survives a
force-quit.

There are only three persisted states — `pending`, `uploaded`, `failed`. There is
deliberately no `uploading`: the moment a process dies mid-request, that state
would be a lie, and recovering from it would mean scanning for orphans on every
launch. Instead the attempt is journalled before the request goes out and the
record stays `pending` until an outcome arrives. After a crash it is already in
the right state with no recovery pass at all.

What makes that safe is the idempotency key: generated once when the shutter
fires, never regenerated. A timeout leaves the outcome genuinely unknown — the
shot may have been stored — and only an unchanged key lets the server recognise
the retry and answer `200 duplicate` instead of storing it twice.

The journal is append-only. A single write plus `synchronize` is either fully on
disk or absent; rewriting a record in place can be interrupted halfway and leave
a corrupt one. A torn final line is discarded on replay and everything before it
stands.

### Backoff policy

`min(60, 2 × 2^(n-1)) × jitter(0.5…1.5)`, five attempts, then terminal.

Base 2s is long enough for a network hiccup to pass and short enough that the
user does not notice. Doubling means a server that is genuinely down is not
hammered. The 60s cap stops the curve running into hours, so a recovering server
is reached within a minute rather than after a sleep.

Jitter is applied *after* the cap, not before: capped retries would otherwise all
pin to exactly 60s and lose their spread precisely when the most records are
waiting.

A `Retry-After` hint always wins over the curve — the server knows when it will
be ready — but is itself capped, since an hour-long hint would strand a queue
that only runs in the foreground.

Five attempts cover about 62 seconds. A longer outage exhausts them and the
record goes to `failed`, retryable by hand from the Queue screen with its
attempt budget reset. Retrying for longer would only help while the app stays in
the foreground — background upload is out of scope — so the trade is deliberate:
recover from a hiccup automatically, surface anything worse rather than draining
the battery in silence.

## What I traded away

`FrameGateCore` is a real Swift package and carries the parser, frame source,
metrics, reducer and queue. The app target keeps only the SwiftUI screens and
composition root, wired by hand rather than through a DI framework. That leaves
module boundaries around the code that is worth testing while keeping the demo
app easy to open and run.

Sharpness is measured as mean neighbour difference rather than Laplacian
variance or Tenengrad: the cheapest operator that separates the test patterns,
since this runs thirty times a second.

A fixed sharpness baseline is calibrated on the reference checkerboard rather
than normalizing against the ROI's own local contrast, which would cost a second
pass over the pixels per frame.

Five backoff attempts cover about a minute rather than a longer retry budget:
background upload is out of scope, so retrying past what the foreground session
can cover would not help.

## What I knowingly cut

Real `AVCaptureSession` — explicitly an unscored stretch goal, and unverifiable
on Simulator regardless.

Device rotation handling in the demo: `CaptureViewModel` reports a fixed
`.portrait` orientation. The `ROIMapper` itself is fully tested across all four
`DisplayOrientation` cases; only the live wiring from `UIDevice` to that
parameter is not connected in this build.

A burst/multi-frame step kind: `StepKind` reserves the space, but only `single`
is implemented.

Thumbnails, sections, and swipe actions in Queue — explicitly out of scope.

## What is unverified

Compatibility with Xcode 16 specifically: developed on Xcode 26.6, since Xcode
16 cannot be installed on macOS 26 on this machine.

Behaviour on a physical device: everything was built and verified against the
Simulator and `ReplayFrameSource`, per the brief's constraints.
