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

### Parser behaviour per malformation

| Malformation | Behaviour |
| --- | --- |
| Mixed key casing | |
| Nullable sometimes absent | |
| Number sent as a string | |
| Unknown step kind | |
| Duplicate step id | |
| Declared object that is null | |
| Timestamp with no timezone | |
| Decimal that must not become a Double | |
| Unknown keys | |

### Applied defaults

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
