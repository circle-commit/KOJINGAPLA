//
//  CameraPreview.swift
//  Glass
//
//  Created by JoMinHui on 4/10/26.
//

import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        print("[BBoxDebug] CameraPreview makeUIView bounds=\(Int(view.bounds.width))x\(Int(view.bounds.height))")
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let previewView = uiView as? PreviewView else { return }
        previewView.previewLayer.session = session
        previewView.previewLayer.videoGravity = .resizeAspectFill
        print("[BBoxDebug] CameraPreview update bounds=\(Int(uiView.bounds.width))x\(Int(uiView.bounds.height))")
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
