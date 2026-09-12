# FrameGate

## Running it

Built with Xcode 26.6 on macOS 26.4 (Apple M5), swift-tools-version 6.0,
deployment target iOS 17.0. Xcode 16 cannot be installed on macOS 26, so
compatibility with that version is unverified.

SwiftLint runs as a build phase with `force_unwrapping` set to error. If SwiftLint
is not installed (`brew install swiftlint`), the phase logs a warning and the build
continues.

### The app

### The tests

### The mock server

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

### Applied defaults

| Situation | Default |
| --- | --- |
| An entire threshold is missing | The documented per-metric default (values calibrated against the generated patterns) |
| Only `exit` is missing | `exit = enter`, i.e. no hysteresis band for that metric |
| `holdFrames` is missing | 5 |
| `label` is missing | Falls back to `id` |

## Frame source

## ROI mapping

## Metrics

### Sharpness

### Exposure

### Motion

### Sharpness baseline

## Gate

### States

### Smoothing and hysteresis

## Upload queue

### Manifest

### Durability semantics

### Backoff policy

## What I traded away

## What I knowingly cut

## What is unverified
