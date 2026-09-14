//
//  JPEGEncoder.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Encodes one accepted shot to JPEG. It runs only when a capture request is
/// accepted, never on steady-state frames. Encoding finishes before the source
/// frame callback returns, so the `CVPixelBuffer` is not retained by the pipeline.
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
