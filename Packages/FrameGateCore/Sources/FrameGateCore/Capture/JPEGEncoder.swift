//
//  JPEGEncoder.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Encodes one accepted shot to JPEG. This runs once per capture, never on the
/// per-frame path — the ban on CGImage/CoreImage in the brief is about the
/// steady-state measurement loop, not about saving the shot the gate armed.
public enum JPEGEncoder {

    public static func encode(_ buffer: CVPixelBuffer, quality: CGFloat = 0.9) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }

        CGImageDestinationAddImage(
            destination, cgImage,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
