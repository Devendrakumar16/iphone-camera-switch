//
//  CameraPreviewView.swift
//  iphone camera switch
//
//  Created by Devendra Kumar on 27/10/26.
//

import SwiftUI
import AVFoundation

public struct CameraPreviewView: UIViewRepresentable {
    public let session: AVCaptureSession
    public let onFocusTapped: ((CGPoint) -> Void)?

    public init(session: AVCaptureSession, onFocusTapped: ((CGPoint) -> Void)? = nil) {
        self.session = session
        self.onFocusTapped = onFocusTapped
    }

    public func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onFocusTapped = onFocusTapped
        return view
    }

    public func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.previewLayer.session != session {
            uiView.previewLayer.session = session
        }
    }
}

public class PreviewUIView: UIView {
    public var onFocusTapped: ((CGPoint) -> Void)?

    private var focusBoxView: UIView?

    public override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    public var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestures()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        let capturePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        onFocusTapped?(capturePoint)
        showFocusBox(at: point)
    }

    private func showFocusBox(at point: CGPoint) {
        focusBoxView?.removeFromSuperview()

        let boxSize: CGFloat = 72
        let box = UIView(frame: CGRect(x: point.x - boxSize/2, y: point.y - boxSize/2, width: boxSize, height: boxSize))
        box.layer.borderColor = UIColor.systemYellow.cgColor
        box.layer.borderWidth = 1.5
        box.layer.cornerRadius = 8
        box.backgroundColor = .clear
        box.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
        box.alpha = 0

        addSubview(box)
        focusBoxView = box

        UIView.animate(withDuration: 0.25, animations: {
            box.alpha = 1
            box.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 0.8, options: .curveEaseOut, animations: {
                box.alpha = 0
            }) { _ in
                box.removeFromSuperview()
            }
        }
    }
}
