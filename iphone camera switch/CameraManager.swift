//
//  CameraManager.swift
//  iphone camera switch
//
//  Created by Devendra Kumar on 27/10/26.
//

import Foundation
import Combine
import AVFoundation
import Photos
import SwiftUI
import Metal
import CoreImage
import VideoToolbox

// MARK: - Camera Position
public enum CameraPosition: Sendable {
    case back
    case front
}

// MARK: - CameraManager (MainActor ObservableObject for SwiftUI)
@MainActor
public final class CameraManager: ObservableObject {
    // UI State
    @Published public var isRecording = false
    @Published public var recordingDuration: TimeInterval = 0
    @Published public var formattedDuration: String = "00:00"
    @Published public var currentPosition: CameraPosition = .back
    @Published public var isSwitching = false
    @Published public var activeResolutionString: String = "4K"
    @Published public var activeFrameRateString: String = "60 FPS"
    @Published public var lastSavedThumbnail: UIImage? = nil
    @Published public var statusMessage: String? = nil
    @Published public var hasPermission = false
    @Published public var isSaving = false
    @Published public var showSavedNotification = false
    @Published public var savedNotificationMessage = "4K 60FPS Video saved to Photos!"
    @Published public var isTorchOn = false

    // Dual Mode properties
    @Published public var isDualMode = false
    @Published public var widePreviewImage: UIImage? = nil

    // Computed aliases for UI compatibility
    public var hasPermissions: Bool { hasPermission }
    public var isSwitchingCamera: Bool { isSwitching }
    public var permissionError: String? { statusMessage }
    public var activeQualityLabel: String { "\(activeResolutionString) • \(activeFrameRateString)" }
    public var isFlashAvailable: Bool {
        engine.isTorchAvailable
    }

    public var captureSession: AVCaptureSession {
        engine.captureSession
    }

    private let engine = CaptureEngine()
    private var timer: Timer?

    public init() {
        engine.delegate = self
        self.currentPosition = engine.currentPosition
        checkPermissions()
    }

    public func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                self.hasPermission = true
                self.engine.startSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    Task { @MainActor in
                        if granted {
                            self?.hasPermission = true
                            self?.engine.startSession()
                        } else {
                            self?.statusMessage = "Microphone access required for video recording."
                        }
                    }
                }
            default:
                self.statusMessage = "Microphone permission denied. Enable in Settings."
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.checkPermissions()
                    } else {
                        self?.statusMessage = "Camera permission denied. Enable in Settings."
                    }
                }
            }
        default:
            self.statusMessage = "Camera permission denied. Enable in Settings."
        }
    }

    public func toggleDualMode() {
        guard !isRecording else { return }
        isDualMode.toggle()
        engine.isDualMode = isDualMode
        if !isDualMode {
            widePreviewImage = nil
        }
    }

    public func startRecording() {
        guard !isRecording else { return }
        self.statusMessage = nil
        self.showSavedNotification = false
        self.engine.startRecording()
    }

    public func stopRecording() {
        guard isRecording else { return }
        self.isRecording = false
        self.isSaving = true
        self.stopTimer()
        self.engine.stopRecording()
    }

    public func switchCamera() {
        guard !isSwitching else { return }
        self.isSwitching = true
        let nextPosition: CameraPosition = (currentPosition == .back) ? .front : .back
        self.engine.switchCamera(to: nextPosition)
    }

    public func toggleTorch() {
        isTorchOn.toggle()
        engine.setTorch(on: isTorchOn)
    }

    public func focusAndExpose(at point: CGPoint) {
        self.engine.focusAndExpose(at: point)
    }

    private func startTimer() {
        stopTimer()
        let start = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let duration = Date().timeIntervalSince(start)
            self.recordingDuration = duration
            let mins = Int(duration) / 60
            let secs = Int(duration) % 60
            self.formattedDuration = String(format: "%02d:%02d", mins, secs)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - CaptureEngineDelegate
extension CameraManager: CaptureEngineDelegate {
    nonisolated public func engineDidStartRecording() {
        Task { @MainActor in
            self.isRecording = true
            self.recordingDuration = 0
            self.formattedDuration = "00:00"
            self.startTimer()
        }
    }

    nonisolated public func engineDidFailRecording(error: String) {
        Task { @MainActor in
            self.isRecording = false
            self.isSaving = false
            self.stopTimer()
            self.statusMessage = error
        }
    }

    nonisolated public func engineDidFinishSaving(thumbnail: UIImage?, message: String) {
        Task { @MainActor in
            self.isSaving = false
            if let thumb = thumbnail {
                self.lastSavedThumbnail = thumb
            }
            self.savedNotificationMessage = message
            withAnimation(.spring()) {
                self.showSavedNotification = true
            }

            // Auto-hide toast after 3.5 seconds
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            withAnimation(.easeInOut(duration: 0.3)) {
                self.showSavedNotification = false
            }
        }
    }

    nonisolated public func engineDidSwitchCamera(to position: CameraPosition, resolution: String, fps: String) {
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.25)) {
                self.currentPosition = position
                self.activeResolutionString = resolution
                self.activeFrameRateString = fps
                self.isSwitching = false
                if position == .front && self.isTorchOn {
                    self.isTorchOn = false
                }
            }
        }
    }

    nonisolated public func engineDidUpdateStatus(_ message: String) {
        Task { @MainActor in
            self.statusMessage = message
        }
    }

    nonisolated public func engineDidUpdateWidePreview(image: UIImage) {
        Task { @MainActor in
            self.widePreviewImage = image
        }
    }
}

// MARK: - Delegate Protocol
public protocol CaptureEngineDelegate: AnyObject, Sendable {
    func engineDidStartRecording()
    func engineDidFailRecording(error: String)
    func engineDidFinishSaving(thumbnail: UIImage?, message: String)
    func engineDidSwitchCamera(to position: CameraPosition, resolution: String, fps: String)
    func engineDidUpdateStatus(_ message: String)
    func engineDidUpdateWidePreview(image: UIImage)
}

// MARK: - Thread-Safe CaptureEngine
public final class CaptureEngine: NSObject, @unchecked Sendable {
    public weak var delegate: CaptureEngineDelegate?

    public let captureSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()

    private let sessionQueue = DispatchQueue(label: "com.camera.engine.sessionQueue")
    private let videoOutputQueue = DispatchQueue(label: "com.camera.engine.videoOutputQueue", qos: .userInteractive)
    private let audioOutputQueue = DispatchQueue(label: "com.camera.engine.audioOutputQueue", qos: .userInteractive)

    // AVAssetWriter Engine (Primary: 9:16 Natural Portrait)
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var currentRecordingURL: URL?

    // Secondary AVAssetWriter Engine (Dual Mode: 16:9 Wide Angle covering all area)
    public var isDualMode: Bool = false
    private var wideAssetWriter: AVAssetWriter?
    private var wideVideoWriterInput: AVAssetWriterInput?
    private var wideAudioWriterInput: AVAssetWriterInput?
    private var widePixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var currentWideRecordingURL: URL?
    private var isWideWriterSessionStarted = false
    private var lastWideVideoPTS: CMTime = .invalid
    private var lastWideAudioPTS: CMTime = .invalid

    // Sync & Timing
    private let writerLock = NSLock()
    private var isWriterSessionStarted = false
    private var lastVideoPTS: CMTime = .invalid
    private var lastAudioPTS: CMTime = .invalid

    // Target Dimensions (Preserving 16:9 / 9:16 exact aspect ratios without distortion)
    public let targetWidth: Int = 2160       // 9:16 Portrait
    public let targetHeight: Int = 3840
    public let wideTargetWidth: Int = 3840   // 16:9 Wide Angle
    public let wideTargetHeight: Int = 2160

    private var frameCounter: Int = 0

    // Metal-accelerated CoreImage context for GPU transformation
    private let ciContext: CIContext = {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: metalDevice)
        }
        return CIContext()
    }()
    public private(set) var currentPosition: CameraPosition = .back

    public var isTorchAvailable: Bool {
        guard let device = videoDeviceInput?.device else { return false }
        return device.hasTorch && device.isTorchAvailable
    }

    public override init() {
        super.init()
    }

    public func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .inputPriority

            // Video Input: Initial standard rear camera (1x)
            if let videoDevice = self.cameraDevice(for: self.currentPosition) {
                do {
                    let input = try AVCaptureDeviceInput(device: videoDevice)
                    if self.captureSession.canAddInput(input) {
                        self.captureSession.addInput(input)
                        self.videoDeviceInput = input
                        self.configure4K60FPS(for: videoDevice)
                    }
                } catch {
                    print("Error setting initial video input: \(error)")
                }
            }

            // Audio Input
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                do {
                    let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                    if self.captureSession.canAddInput(audioInput) {
                        self.captureSession.addInput(audioInput)
                        self.audioDeviceInput = audioInput
                    }
                } catch {
                    print("Error setting audio input: \(error)")
                }
            }

            // Video Data Output
            self.videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            self.videoDataOutput.alwaysDiscardsLateVideoFrames = false
            self.videoDataOutput.setSampleBufferDelegate(self, queue: self.videoOutputQueue)
            if self.captureSession.canAddOutput(self.videoDataOutput) {
                self.captureSession.addOutput(self.videoDataOutput)
            }

            // Audio Data Output
            self.audioDataOutput.setSampleBufferDelegate(self, queue: self.audioOutputQueue)
            if self.captureSession.canAddOutput(self.audioDataOutput) {
                self.captureSession.addOutput(self.audioDataOutput)
            }

            self.updateVideoConnection(for: self.currentPosition)

            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        }
    }

    private func updateVideoConnection(for position: CameraPosition) {
        if let connection = self.videoDataOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .cinematicExtended
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = (position == .front)
            }
        }
    }

    private func cameraDevice(for position: CameraPosition) -> AVCaptureDevice? {
        if position == .back {
            // Strictly the standard primary rear camera (1x) - never changes zoom or optical lens
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video)
        } else {
            // Strictly the standard front camera (selfie)
            return AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
    }

    @discardableResult
    private func configure4K60FPS(for device: AVCaptureDevice) -> (resolution: String, fps: String) {
        var resLabel = "4K"
        var fpsLabel = "60 FPS"

        do {
            try device.lockForConfiguration()

            // Strictly lock zoom to 1.0 (no zoom in or zoom out)
            device.videoZoomFactor = 1.0

            var bestFormat: AVCaptureDevice.Format? = nil
            var bestScore = -1
            var bestDimensions = CMVideoDimensions(width: 0, height: 0)
            var chosenRate: Double = 60.0

            for format in device.formats {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let maxDim = max(dimensions.width, dimensions.height)
                let minDim = min(dimensions.width, dimensions.height)
                guard minDim > 0 else { continue }
                let aspectRatio = Double(maxDim) / Double(minDim)
                let is16by9 = abs(aspectRatio - (16.0 / 9.0)) < 0.05
                let is4K = (maxDim >= 3840 && minDim >= 2160)
                let is1080p = (maxDim >= 1920 && minDim >= 1080)

                for range in format.videoSupportedFrameRateRanges {
                    var score = 0

                    // 16:9 aspect ratio is paramount to match standard video without stretching
                    if is16by9 {
                        score += 10_000_000
                    }

                    if is4K {
                        score += 5_000_000
                    } else if is1080p {
                        score += 1_000_000
                    } else {
                        score += Int(maxDim * minDim) / 10
                    }

                    if range.maxFrameRate >= 59.9 {
                        score += 2_000_000
                    } else if range.maxFrameRate >= 29.9 {
                        score += 500_000
                    }

                    if format.isVideoHDRSupported {
                        score += 50_000
                    }

                    if format.supportedColorSpaces.contains(.P3_D65) {
                        score += 10_000
                    }

                    if format.isVideoStabilizationModeSupported(.cinematicExtended) {
                        score += 5_000
                    }

                    if score > bestScore {
                        bestScore = score
                        bestFormat = format
                        bestDimensions = dimensions
                        chosenRate = min(60.0, range.maxFrameRate)
                    }
                }
            }

            if let format = bestFormat {
                device.activeFormat = format
                let frameDuration = CMTime(value: 1, timescale: CMTimeScale(chosenRate))
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration

                if format.isVideoHDRSupported {
                    device.automaticallyAdjustsVideoHDREnabled = false
                    device.isVideoHDREnabled = true
                }

                if format.supportedColorSpaces.contains(.P3_D65) {
                    device.activeColorSpace = .P3_D65
                }

                resLabel = (bestDimensions.width >= 3840 || bestDimensions.height >= 3840) ? "4K" : "\(min(bestDimensions.width, bestDimensions.height))p"
                fpsLabel = "\(Int(round(chosenRate))) FPS"
            }

            // Maintain 1.0x standard zoom
            device.videoZoomFactor = 1.0

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
            }

            device.unlockForConfiguration()
        } catch {
            print("Could not configure device for clearest quality: \(error)")
        }

        return (resLabel, fpsLabel)
    }

    // MARK: - Seamless Flip During Recording (Strictly Rear <-> Front, No Zoom Changes)
    public func switchCamera(to newPosition: CameraPosition) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            guard let newDevice = self.cameraDevice(for: newPosition) else {
                self.delegate?.engineDidSwitchCamera(to: self.currentPosition, resolution: "4K", fps: "60 FPS")
                return
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)

                self.captureSession.beginConfiguration()

                if let currentInput = self.videoDeviceInput {
                    self.captureSession.removeInput(currentInput)
                }

                var labels = ("4K", "60 FPS")
                if self.captureSession.canAddInput(newInput) {
                    self.captureSession.addInput(newInput)
                    self.videoDeviceInput = newInput
                    labels = self.configure4K60FPS(for: newDevice)
                } else if let currentInput = self.videoDeviceInput {
                    self.captureSession.addInput(currentInput)
                }

                self.updateVideoConnection(for: newPosition)

                self.captureSession.commitConfiguration()

                self.currentPosition = newPosition
                self.delegate?.engineDidSwitchCamera(to: newPosition, resolution: labels.0, fps: labels.1)
            } catch {
                print("Failed to switch camera device: \(error)")
                self.delegate?.engineDidSwitchCamera(to: self.currentPosition, resolution: "4K", fps: "60 FPS")
            }
        }
    }

    public func setTorch(on: Bool) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoDeviceInput?.device, device.hasTorch, device.isTorchAvailable else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
            } catch {
                print("Error setting torch: \(error)")
            }
        }
    }

    // MARK: - Start Recording
    public func startRecording() {
        let outputFileName = UUID().uuidString + "_portrait.mp4"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)
        try? FileManager.default.removeItem(at: outputURL)
        self.currentRecordingURL = outputURL

        var wideOutputURL: URL? = nil
        if isDualMode {
            let wideFileName = UUID().uuidString + "_wide.mp4"
            let wURL = FileManager.default.temporaryDirectory.appendingPathComponent(wideFileName)
            try? FileManager.default.removeItem(at: wURL)
            self.currentWideRecordingURL = wURL
            wideOutputURL = wURL
        } else {
            self.currentWideRecordingURL = nil
        }

        do {
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

            // Ultra High Quality 4K HEVC Video Configuration (85 Mbps Master Clarity)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: targetWidth,
                AVVideoHeightKey: targetHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 85_000_000,
                    AVVideoExpectedSourceFrameRateKey: 60,
                    AVVideoMaxKeyFrameIntervalKey: 60,
                    AVVideoAllowFrameReorderingKey: true,
                    AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel
                ]
            ]

            let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            vInput.expectsMediaDataInRealTime = true

            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: targetWidth,
                kCVPixelBufferHeightKey as String: targetHeight,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]

            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: vInput,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )

            if writer.canAdd(vInput) {
                writer.add(vInput)
            }

            // High Fidelity Studio Stereo AAC Audio Configuration (48kHz, 256kbps)
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48000.0,
                AVEncoderBitRateKey: 256000
            ]

            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true

            if writer.canAdd(aInput) {
                writer.add(aInput)
            }

            // Setup Wide Writer if Dual Mode is active
            var wWriter: AVAssetWriter? = nil
            var wVInput: AVAssetWriterInput? = nil
            var wAInput: AVAssetWriterInput? = nil
            var wAdaptor: AVAssetWriterInputPixelBufferAdaptor? = nil

            if let wURL = wideOutputURL {
                let wideWriter = try AVAssetWriter(outputURL: wURL, fileType: .mp4)

                let wideVideoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.hevc,
                    AVVideoWidthKey: wideTargetWidth,
                    AVVideoHeightKey: wideTargetHeight,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: 85_000_000,
                        AVVideoExpectedSourceFrameRateKey: 60,
                        AVVideoMaxKeyFrameIntervalKey: 60,
                        AVVideoAllowFrameReorderingKey: true,
                        AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel
                    ]
                ]

                let wideVInput = AVAssetWriterInput(mediaType: .video, outputSettings: wideVideoSettings)
                wideVInput.expectsMediaDataInRealTime = true

                let wideSourcePixelBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                    kCVPixelBufferWidthKey as String: wideTargetWidth,
                    kCVPixelBufferHeightKey as String: wideTargetHeight,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ]

                let wideAdapt = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: wideVInput,
                    sourcePixelBufferAttributes: wideSourcePixelBufferAttributes
                )

                if wideWriter.canAdd(wideVInput) {
                    wideWriter.add(wideVInput)
                }

                let wideAInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                wideAInput.expectsMediaDataInRealTime = true
                if wideWriter.canAdd(wideAInput) {
                    wideWriter.add(wideAInput)
                }

                wWriter = wideWriter
                wVInput = wideVInput
                wAInput = wideAInput
                wAdaptor = wideAdapt
            }

            // Start writing on both writers before exposing them to the capture queue
            writer.startWriting()
            wWriter?.startWriting()

            self.writerLock.lock()
            self.assetWriter = writer
            self.videoWriterInput = vInput
            self.audioWriterInput = aInput
            self.pixelBufferAdaptor = adaptor
            self.lastVideoPTS = .invalid
            self.lastAudioPTS = .invalid
            self.isWriterSessionStarted = false

            self.wideAssetWriter = wWriter
            self.wideVideoWriterInput = wVInput
            self.wideAudioWriterInput = wAInput
            self.widePixelBufferAdaptor = wAdaptor
            self.lastWideVideoPTS = .invalid
            self.lastWideAudioPTS = .invalid
            self.isWideWriterSessionStarted = false
            self.writerLock.unlock()

            self.delegate?.engineDidStartRecording()
        } catch {
            self.delegate?.engineDidFailRecording(error: "Recorder error: \(error.localizedDescription)")
        }
    }

    // MARK: - Stop Recording
    public func stopRecording() {
        self.writerLock.lock()
        guard let writer = self.assetWriter else {
            self.writerLock.unlock()
            return
        }

        self.isWriterSessionStarted = false
        self.isWideWriterSessionStarted = false

        self.videoWriterInput?.markAsFinished()
        self.audioWriterInput?.markAsFinished()

        let wideWriter = self.wideAssetWriter
        self.wideVideoWriterInput?.markAsFinished()
        self.wideAudioWriterInput?.markAsFinished()
        self.writerLock.unlock()

        let portraitURL = self.currentRecordingURL
        let wideURL = self.currentWideRecordingURL
        let isDual = (wideWriter != nil && wideURL != nil)

        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        writer.finishWriting {
            dispatchGroup.leave()
        }

        if let ww = wideWriter {
            dispatchGroup.enter()
            ww.finishWriting {
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            if writer.status == .completed, let pURL = portraitURL {
                if isDual, let wURL = wideURL, wideWriter?.status == .completed {
                    self.saveDualVideosToPhotos(portraitURL: pURL, wideURL: wURL)
                } else {
                    self.saveVideoToPhotos(at: pURL)
                }
            } else {
                let err = writer.error?.localizedDescription ?? "Recording completion failed"
                self.delegate?.engineDidFailRecording(error: err)
            }

            self.writerLock.lock()
            self.assetWriter = nil
            self.videoWriterInput = nil
            self.audioWriterInput = nil
            self.pixelBufferAdaptor = nil
            self.wideAssetWriter = nil
            self.wideVideoWriterInput = nil
            self.wideAudioWriterInput = nil
            self.widePixelBufferAdaptor = nil
            self.writerLock.unlock()
        }
    }

    private func saveVideoToPhotos(at fileURL: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                self?.delegate?.engineDidUpdateStatus("Photo library access denied.")
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }) { success, error in
                if success {
                    self?.generateThumbnailAndComplete(from: fileURL, isDual: false)
                } else {
                    let err = error?.localizedDescription ?? "Could not save video."
                    self?.delegate?.engineDidUpdateStatus("Failed to save: \(err)")
                }
            }
        }
    }

    private func saveDualVideosToPhotos(portraitURL: URL, wideURL: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                self?.delegate?.engineDidUpdateStatus("Photo library access denied.")
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: portraitURL)
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: wideURL)
            }) { success, error in
                if success {
                    self?.generateThumbnailAndComplete(from: portraitURL, isDual: true)
                    try? FileManager.default.removeItem(at: wideURL)
                } else {
                    let err = error?.localizedDescription ?? "Could not save dual videos."
                    self?.delegate?.engineDidUpdateStatus("Failed to save dual videos: \(err)")
                }
            }
        }
    }

    private func generateThumbnailAndComplete(from url: URL, isDual: Bool = false) {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)

        let time = CMTime(seconds: 0.1, preferredTimescale: 60)
        var thumbnailImage: UIImage? = nil
        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
            thumbnailImage = UIImage(cgImage: cgImage)
        }

        try? FileManager.default.removeItem(at: url)
        let msg = isDual ? "Dual 4K Videos saved (Portrait & Wide)!" : "4K 60FPS Video saved to Photos!"
        self.delegate?.engineDidFinishSaving(thumbnail: thumbnailImage, message: msg)
    }

    public func focusAndExpose(at point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {
                print("Error setting focus: \(error)")
            }
        }
    }

    // Mini 100x100 Live Wide Angle Preview Generator
    private func generateWidePreview(from buffer: CVPixelBuffer) {
        let sourceWidth = CVPixelBufferGetWidth(buffer)
        let sourceHeight = CVPixelBufferGetHeight(buffer)

        var ciImage = CIImage(cvPixelBuffer: buffer)
        if sourceWidth < sourceHeight {
            ciImage = ciImage.oriented(.left)
        }
        let isFront = (self.currentPosition == .front)
        let isConnectionMirrored = (self.videoDataOutput.connection(with: .video)?.isVideoMirrored == true)
        if isFront && !isConnectionMirrored {
            ciImage = ciImage.oriented(.upMirrored)
        }

        let origin = ciImage.extent.origin
        if origin.x != 0 || origin.y != 0 {
            ciImage = ciImage.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
        }

        let maxDim = max(ciImage.extent.width, ciImage.extent.height)
        guard maxDim > 0 else { return }
        let scale = 140.0 / maxDim
        let thumb = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        if let cgImage = self.ciContext.createCGImage(thumb, from: thumb.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            self.delegate?.engineDidUpdateWidePreview(image: uiImage)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate & Audio Delegate
extension CaptureEngine: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let isVideo = (output is AVCaptureVideoDataOutput)

        // Live Wide Angle 100x100 preview generator (sampled at ~20fps for silky responsiveness)
        if isVideo && self.isDualMode {
            self.frameCounter += 1
            if self.frameCounter % 3 == 0 {
                if let previewBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    self.generateWidePreview(from: previewBuffer)
                }
            }
        }

        writerLock.lock()
        defer { writerLock.unlock() }

        guard let writer = self.assetWriter, writer.status == .writing else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid else { return }

        // Start writer session with first valid video frame for BOTH writers synchronously
        if !self.isWriterSessionStarted {
            guard isVideo else { return }
            guard writer.status == .writing else { return }

            if self.isDualMode {
                guard let wideWriter = self.wideAssetWriter, wideWriter.status == .writing else {
                    return
                }
                wideWriter.startSession(atSourceTime: presentationTime)
                self.isWideWriterSessionStarted = true
            }

            writer.startSession(atSourceTime: presentationTime)
            self.isWriterSessionStarted = true
        }

        guard self.isWriterSessionStarted else { return }
        if self.isDualMode && !self.isWideWriterSessionStarted {
            return
        }

        if isVideo {
            self.handleVideoFrame(sampleBuffer: sampleBuffer, pts: presentationTime)
        } else {
            self.handleAudioFrame(sampleBuffer: sampleBuffer, pts: presentationTime)
        }
    }

    private func handleVideoFrame(sampleBuffer: CMSampleBuffer, pts: CMTime) {
        guard let vInput = self.videoWriterInput,
              let adaptor = self.pixelBufferAdaptor,
              vInput.isReadyForMoreMediaData else {
            return
        }

        // Monotonic PTS check: strictly guarantee timestamps increase across camera switch
        var validPTS = pts
        if self.lastVideoPTS.isValid && validPTS <= self.lastVideoPTS {
            validPTS = CMTimeAdd(self.lastVideoPTS, CMTime(value: 1, timescale: 600))
        }
        self.lastVideoPTS = validPTS

        guard let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let sourceWidth = CVPixelBufferGetWidth(sourcePixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourcePixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0 else { return }

        let isFront = (self.currentPosition == .front)
        let isConnectionMirrored = (self.videoDataOutput.connection(with: .video)?.isVideoMirrored == true)
        let needsMirroring = (isFront && !isConnectionMirrored)

        // 1. Process and append to Portrait Adaptor (2160 x 3840, 9:16 natural portrait)
        if let pool = adaptor.pixelBufferPool {
            var destinationPixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destinationPixelBuffer)
            if status == kCVReturnSuccess, let destBuffer = destinationPixelBuffer {
                var ciImage = CIImage(cvPixelBuffer: sourcePixelBuffer)

                // Rotate landscape buffer into portrait (90 deg clockwise)
                if sourceWidth > sourceHeight {
                    ciImage = ciImage.oriented(.right)
                }

                // Front camera horizontal mirroring if not handled by connection
                if needsMirroring {
                    ciImage = ciImage.oriented(.upMirrored)
                }

                // Normalize extent origin to (0,0) after orientation transforms
                let origin = ciImage.extent.origin
                if origin.x != 0 || origin.y != 0 {
                    ciImage = ciImage.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
                }

                let curW = ciImage.extent.width
                let curH = ciImage.extent.height
                if curW > 0, curH > 0 {
                    // Uniform aspect-fill scaling to preserve natural proportions without vertical stretching
                    let scale = max(CGFloat(targetWidth) / curW, CGFloat(targetHeight) / curH)
                    var transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

                    // Center-crop to exact target dimensions
                    let sW = transformed.extent.width
                    let sH = transformed.extent.height
                    let cropX = max(0, (sW - CGFloat(targetWidth)) / 2.0)
                    let cropY = max(0, (sH - CGFloat(targetHeight)) / 2.0)
                    let cropRect = CGRect(x: cropX, y: cropY, width: CGFloat(targetWidth), height: CGFloat(targetHeight))
                    transformed = transformed.cropped(to: cropRect)
                    transformed = transformed.transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY))

                    self.ciContext.render(transformed, to: destBuffer)
                    adaptor.append(destBuffer, withPresentationTime: validPTS)
                }
            }
        }

        // 2. If in Dual Mode, process and append to Wide Adaptor (3840 x 2160, 16:9 wide field of view)
        if self.isDualMode,
           self.isWideWriterSessionStarted,
           let wideWriter = self.wideAssetWriter,
           wideWriter.status == .writing,
           let wideVInput = self.wideVideoWriterInput,
           let wideAdaptor = self.widePixelBufferAdaptor,
           wideVInput.isReadyForMoreMediaData {

            var validWidePTS = pts
            if self.lastWideVideoPTS.isValid && validWidePTS <= self.lastWideVideoPTS {
                validWidePTS = CMTimeAdd(self.lastWideVideoPTS, CMTime(value: 1, timescale: 600))
            }
            self.lastWideVideoPTS = validWidePTS

            if let widePool = wideAdaptor.pixelBufferPool {
                var wideDestPixelBuffer: CVPixelBuffer?
                let wStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, widePool, &wideDestPixelBuffer)
                if wStatus == kCVReturnSuccess, let wideDestBuffer = wideDestPixelBuffer {
                    var wideCI = CIImage(cvPixelBuffer: sourcePixelBuffer)

                    // Ensure wide video is in landscape (3840 x 2160)
                    if sourceWidth < sourceHeight {
                        wideCI = wideCI.oriented(.left)
                    }
                    if needsMirroring {
                        wideCI = wideCI.oriented(.upMirrored)
                    }

                    let wOrigin = wideCI.extent.origin
                    if wOrigin.x != 0 || wOrigin.y != 0 {
                        wideCI = wideCI.transformed(by: CGAffineTransform(translationX: -wOrigin.x, y: -wOrigin.y))
                    }

                    let wCurW = wideCI.extent.width
                    let wCurH = wideCI.extent.height
                    if wCurW > 0, wCurH > 0 {
                        let wScale = max(CGFloat(wideTargetWidth) / wCurW, CGFloat(wideTargetHeight) / wCurH)
                        var wTransformed = wideCI.transformed(by: CGAffineTransform(scaleX: wScale, y: wScale))

                        let wsW = wTransformed.extent.width
                        let wsH = wTransformed.extent.height
                        let wCropX = max(0, (wsW - CGFloat(wideTargetWidth)) / 2.0)
                        let wCropY = max(0, (wsH - CGFloat(wideTargetHeight)) / 2.0)
                        let wCropRect = CGRect(x: wCropX, y: wCropY, width: CGFloat(wideTargetWidth), height: CGFloat(wideTargetHeight))
                        wTransformed = wTransformed.cropped(to: wCropRect)
                        wTransformed = wTransformed.transformed(by: CGAffineTransform(translationX: -wCropX, y: -wCropY))

                        self.ciContext.render(wTransformed, to: wideDestBuffer)
                        wideAdaptor.append(wideDestBuffer, withPresentationTime: validWidePTS)
                    }
                }
            }
        }
    }

    private func handleAudioFrame(sampleBuffer: CMSampleBuffer, pts: CMTime) {
        guard let aInput = self.audioWriterInput, aInput.isReadyForMoreMediaData else {
            return
        }

        if self.lastAudioPTS.isValid && pts <= self.lastAudioPTS {
            return
        }
        self.lastAudioPTS = pts

        aInput.append(sampleBuffer)

        // Feed audio to secondary wide angle writer in perfect synchronization
        if self.isDualMode,
           self.isWideWriterSessionStarted,
           let wideWriter = self.wideAssetWriter,
           wideWriter.status == .writing,
           let wideAInput = self.wideAudioWriterInput,
           wideAInput.isReadyForMoreMediaData {
            wideAInput.append(sampleBuffer)
        }
    }
}
