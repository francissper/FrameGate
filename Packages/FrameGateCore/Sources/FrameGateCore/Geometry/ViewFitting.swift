//
//  ViewFitting.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import CoreGraphics

/// How the buffer's content is laid out inside the view.
enum ViewFitting {

    /// The rect the whole buffer occupies in the view. With aspectFill it
    /// overflows the view; with aspectFit it sits inside with letterboxing.
    static func contentRect(bufferSize: CGSize,
                            viewSize: CGSize,
                            fillMode: FillMode) -> CGRect {
        guard bufferSize.width > 0, bufferSize.height > 0 else { return .zero }

        let bufferAspect = bufferSize.width / bufferSize.height
        let viewAspect = viewSize.width / viewSize.height

        let scale: CGFloat
        switch fillMode {
        case .aspectFill:
            scale = bufferAspect > viewAspect
                ? viewSize.height / bufferSize.height
                : viewSize.width / bufferSize.width
        case .aspectFit:
            scale = bufferAspect > viewAspect
                ? viewSize.width / bufferSize.width
                : viewSize.height / bufferSize.height
        }

        let scaled = CGSize(width: bufferSize.width * scale,
                            height: bufferSize.height * scale)
        return CGRect(x: (viewSize.width - scaled.width) / 2,
                      y: (viewSize.height - scaled.height) / 2,
                      width: scaled.width,
                      height: scaled.height)
    }
}
