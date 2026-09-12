//
//  NormalizedRegion.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 11/09/26.
//

import CoreGraphics

/// A rectangle expressed in 0…1 of the sensor frame, origin top-left.
public struct NormalizedRegion: Equatable, Sendable {
  public let x: CGFloat
  public let y: CGFloat
  public let width: CGFloat
  public let height: CGFloat

  public init?(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
    guard width > 0, height > 0,
          x >= 0, y >= 0,
          x + width <= 1, y + height <= 1 else { return nil }
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}
