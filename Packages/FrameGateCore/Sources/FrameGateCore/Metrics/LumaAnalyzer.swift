//
//  LumaAnalyzer.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import CoreVideo
import CoreGraphics

/// Measures one frame inside the mapped region, reading the Y plane directly.
///
/// Scratch buffers are allocated once here and reused for every frame: the
/// steady-state path allocates nothing. The pixel buffer is never retained past
/// the call — only the downsampled copy survives, and it lives in a fixed-size
/// buffer so a changing ROI never triggers a reallocation.
public final class LumaAnalyzer {

  /// Raw sharpness of the reference checkerboard, measured once and recorded
  /// in the README. Dividing by it makes 1.0 mean "as sharp as the reference".
  public static let sharpnessBaseline: Double = 26.67

  /// A pixel at or below this has lost its shadow detail.
  static let crushThreshold: UInt8 = 5
  /// A pixel at or above this has lost its highlight detail.
  static let blowThreshold: UInt8 = 250

  /// Fixed so the scratch buffer never resizes when the ROI changes between steps.
  static let downsampleSide = 32

  private var current: [UInt8]
  private var previous: [UInt8]
  private var hasPrevious = false

  public init() {
    let count = Self.downsampleSide * Self.downsampleSide
    current = [UInt8](repeating: 0, count: count)
    previous = [UInt8](repeating: 0, count: count)
  }

  /// Measures the region. Returns nil if the buffer cannot be read.
  public func analyze(_ buffer: CVPixelBuffer, region: CGRect) -> FrameMetrics? {
    guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
      return nil
    }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

    guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }

    let planeWidth = CVPixelBufferGetWidthOfPlane(buffer, 0)
    let planeHeight = CVPixelBufferGetHeightOfPlane(buffer, 0)
    let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
    let plane = base.assumingMemoryBound(to: UInt8.self)

    // Clamp the region to the plane: a mapped rect can sit on the edge.
    let left = max(0, Int(region.minX))
    let top = max(0, Int(region.minY))
    let right = min(planeWidth, Int(region.maxX))
    let bottom = min(planeHeight, Int(region.maxY))

    guard right - left >= 2, bottom - top >= 2 else { return nil }

    let exposure = measureExposure(plane, stride: stride,
                                   left: left, top: top, right: right, bottom: bottom)
    let sharpness = measureSharpness(plane, stride: stride,
                                     left: left, top: top, right: right, bottom: bottom)
    let motion = measureMotion(plane, stride: stride,
                               left: left, top: top, right: right, bottom: bottom)

    return FrameMetrics(sharpness: sharpness / Self.sharpnessBaseline,
                        meanLuma: exposure.mean,
                        crushedFraction: exposure.crushed,
                        blownFraction: exposure.blown,
                        motion: motion)
  }

  /// Forgets the previous frame, so the next one reports maximum motion.
  /// Called when the plan advances to a step with a different region.
  public func reset() {
    hasPrevious = false
  }
}

// MARK: - Exposure

private extension LumaAnalyzer {

  struct Exposure {
    let mean: Double
    let crushed: Double
    let blown: Double
  }

  /// Subsamples every other pixel in both directions: a quarter of the reads
  /// for a mean that is statistically identical on any real image.
  func measureExposure(_ plane: UnsafeMutablePointer<UInt8>,
                       stride: Int,
                       left: Int, top: Int, right: Int, bottom: Int) -> Exposure {
    var total = 0
    var crushed = 0
    var blown = 0
    var count = 0

    var row = top
    while row < bottom {
      let line = plane + row * stride
      var column = left
      while column < right {
        let value = line[column]
        total += Int(value)
        if value <= Self.crushThreshold { crushed += 1 }
        if value >= Self.blowThreshold { blown += 1 }
        count += 1
        column += 2
      }
      row += 2
    }

    guard count > 0 else { return Exposure(mean: 0, crushed: 0, blown: 0) }
    let divisor = Double(count)
    return Exposure(mean: Double(total) / divisor / 255,
                    crushed: Double(crushed) / divisor,
                    blown: Double(blown) / divisor)
  }
}

// MARK: - Sharpness

private extension LumaAnalyzer {

  /// Mean absolute difference against the right and lower neighbour. Both
  /// directions so an image with edges in only one axis is not read as flat.
  func measureSharpness(_ plane: UnsafeMutablePointer<UInt8>,
                        stride: Int,
                        left: Int, top: Int, right: Int, bottom: Int) -> Double {
    var total = 0
    var count = 0

    var row = top
    while row < bottom - 1 {
      let line = plane + row * stride
      let next = plane + (row + 1) * stride
      var column = left
      while column < right - 1 {
        let value = Int(line[column])
        total += abs(Int(line[column + 1]) - value)
        total += abs(Int(next[column]) - value)
        count += 2
        column += 1
      }
      row += 1
    }

    guard count > 0 else { return 0 }
    return Double(total) / Double(count)
  }
}

// MARK: - Motion

private extension LumaAnalyzer {

  /// Downsamples the region into the fixed scratch buffer, then compares it
  /// against the previous frame's. The buffers swap rather than reallocate.
  func measureMotion(_ plane: UnsafeMutablePointer<UInt8>,
                     stride: Int,
                     left: Int, top: Int, right: Int, bottom: Int) -> Double {
    let side = Self.downsampleSide
    let width = right - left
    let height = bottom - top

    current.withUnsafeMutableBufferPointer { scratch in
      var cell = 0
      var yCell = 0
      while yCell < side {
        let sampleRow = top + (yCell * height) / side
        let line = plane + sampleRow * stride
        var xCell = 0
        while xCell < side {
          scratch[cell] = line[left + (xCell * width) / side]
          cell += 1
          xCell += 1
        }
        yCell += 1
      }
    }

    guard hasPrevious else {
      swap(&current, &previous)
      hasPrevious = true
      return 1
    }

    var total = 0
    let count = side * side
    for index in 0..<count {
      total += abs(Int(current[index]) - Int(previous[index]))
    }

    swap(&current, &previous)
    return Double(total) / Double(count) / 255
  }
}
