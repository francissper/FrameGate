//
//  NormalizedTransform.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import CoreGraphics

/// Transformations applied in normalized space, before scaling to pixels or points.
/// Composing here means rotation is written once rather than once per combination.
enum NormalizedTransform {

    /// Rotates a normalized rect clockwise. Width and height swap for 90 and 270.
    static func rotated(_ rect: CGRect, by rotation: SensorRotation) -> CGRect {
        switch rotation {
        case .deg0:
            return rect
        case .deg90:
            return CGRect(x: 1 - rect.maxY, y: rect.minX,
                          width: rect.height, height: rect.width)
        case .deg180:
            return CGRect(x: 1 - rect.maxX, y: 1 - rect.maxY,
                          width: rect.width, height: rect.height)
        case .deg270:
            return CGRect(x: rect.minY, y: 1 - rect.maxX,
                          width: rect.height, height: rect.width)
        }
    }

    /// Reflects across the vertical centre line. Applying it twice is the identity.
    static func mirrored(_ rect: CGRect) -> CGRect {
        CGRect(x: 1 - rect.maxX, y: rect.minY,
               width: rect.width, height: rect.height)
    }
}
