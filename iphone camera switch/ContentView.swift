//
//  ContentView.swift
//  iphone camera switch
//
//  Created by Devendra Kumar on 27/10/26.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var flipDegrees: Double = 0
    @State private var pulseRecordDot = false
    @State private var showThumbnailSheet = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.hasPermissions {
                // Live Viewfinder with smooth 3D flip animation
                CameraPreviewView(session: camera.captureSession) { point in
                    camera.focusAndExpose(at: point)
                }
                .rotation3DEffect(.degrees(flipDegrees), axis: (x: 0, y: 1, z: 0))
                .ignoresSafeArea()
                .overlay(
                    // Cinematic subtle vignette for contrast
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.65),
                            Color.clear,
                            Color.clear,
                            Color.black.opacity(0.75)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                )

                // Main Controls Layer
                VStack {
                    // Top Bar
                    topBar
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    Spacer()

                    // Center Switch Camera Flash Banner (brief visual indicator)
                    if camera.isSwitchingCamera {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                            Text("Switching to \(camera.currentPosition == .back ? "Front Camera" : "Rear Camera")...")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.4), radius: 10)
                        .transition(.scale.combined(with: .opacity))
                    }

                    Spacer()

                    // Bottom Controls Bar
                    bottomControlsBar
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                }

                // Saving to Photos Indicator
                if camera.isSaving {
                    ZStack {
                        Color.black.opacity(0.6)
                            .ignoresSafeArea()

                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            Text(camera.isDualMode ? "Saving Dual 4K Videos to Photos..." : "Saving 4K 60FPS Video to Photos...")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(28)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                    }
                    .transition(.opacity)
                }

                // Saved Success Toast
                if camera.showSavedNotification {
                    VStack {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.green)

                            Text(camera.savedNotificationMessage)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                        .padding(.top, 60)

                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
                }

            } else {
                // Permissions Request Screen
                permissionsView
            }
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack(alignment: .center, spacing: 10) {
            // Quality Badge (4K 60FPS)
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                Text(camera.activeQualityLabel)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )

            // Dual Mode Toggle Button (Portrait + Wide Angle)
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    camera.toggleDualMode()
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: camera.isDualMode ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                        .font(.system(size: 12, weight: .bold))
                    Text(camera.isDualMode ? "DUAL ON" : "DUAL")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(camera.isDualMode ? .cyan : .white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(camera.isDualMode ? Color.cyan.opacity(0.25) : Color.white.opacity(0.12))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(camera.isDualMode ? Color.cyan.opacity(0.8) : Color.white.opacity(0.25), lineWidth: 1)
                )
            }
            .disabled(camera.isRecording)
            .opacity(camera.isRecording ? 0.6 : 1.0)
            .accessibilityLabel("Toggle Dual Mode Recording")

            Spacer()

            // Recording Timer Badge (Pulsing Red Pill)
            if camera.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .opacity(pulseRecordDot ? 1.0 : 0.2)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulseRecordDot)
                        .onAppear { pulseRecordDot = true }
                        .onDisappear { pulseRecordDot = false }

                    Text(formatDuration(camera.recordingDuration))
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.65))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.red.opacity(0.7), lineWidth: 1.5)
                )
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            // Torch Toggle (if available)
            if camera.isFlashAvailable {
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    camera.toggleTorch()
                }) {
                    Image(systemName: camera.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(camera.isTorchOn ? .yellow : .white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            } else {
                Color.clear
                    .frame(width: 38, height: 38)
            }
        }
    }

    // MARK: - Bottom Controls Bar
    private var bottomControlsBar: some View {
        HStack(alignment: .bottom) {
            // Left: Saved Video Thumbnail or Photos Gallery Button
            photoThumbnailButton
                .padding(.bottom, 14)

            Spacer()

            // Center: 100x100 Mini Wide Preview (Dual Mode) + Big Record Button
            VStack(spacing: 14) {
                if camera.isDualMode {
                    miniWideAnglePreview
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                recordButton
            }

            Spacer()

            // Right: Camera Switch Button (Works Seamlessly DURING Recording!)
            switchCameraButton
                .padding(.bottom, 12)
        }
    }

    // MARK: - 100x100 Mini Wide Angle Preview Box
    private var miniWideAnglePreview: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let wideImg = camera.widePreviewImage {
                    Image(uiImage: wideImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipped()
                } else {
                    ZStack {
                        Color.black.opacity(0.7)
                        VStack(spacing: 6) {
                            Image(systemName: "camera.metering.matrix")
                                .font(.system(size: 24))
                                .foregroundColor(.cyan)
                            Text("WIDE 16:9")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .frame(width: 100, height: 100)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: camera.isRecording ? [.red, .orange] : [.cyan.opacity(0.85), .white.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: .black.opacity(0.55), radius: 8, y: 4)

            // Small Corner Tag Indicating Wide Angle Capture
            HStack(spacing: 3) {
                Circle()
                    .fill(camera.isRecording ? Color.red : Color.cyan)
                    .frame(width: 5, height: 5)
                Text("WIDE")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.75))
            .clipShape(Capsule())
            .padding(6)
        }
        .frame(width: 100, height: 100)
        .accessibilityLabel("Wide Angle 100x100 Mini Preview")
    }

    // MARK: - Record Button
    private var recordButton: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()

            if camera.isRecording {
                camera.stopRecording()
            } else {
                camera.startRecording()
            }
        }) {
            ZStack {
                // Outer Ring
                Circle()
                    .stroke(camera.isRecording ? Color.red.opacity(0.85) : Color.white, lineWidth: 4)
                    .frame(width: 82, height: 82)

                if camera.isRecording {
                    // Pulsing Halo Glow
                    Circle()
                        .stroke(Color.red.opacity(0.35), lineWidth: 8)
                        .frame(width: 94, height: 94)
                        .scaleEffect(pulseRecordDot ? 1.05 : 0.95)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseRecordDot)
                }

                // Inner Record/Stop Shape
                if camera.isRecording {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red)
                        .frame(width: 32, height: 32)
                        .transition(.scale)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 66, height: 66)
                        .transition(.scale)
                }
            }
        }
        .accessibilityLabel(camera.isRecording ? "End Recording" : "Start Recording")
    }

    // MARK: - Photo Thumbnail Button
    private var photoThumbnailButton: some View {
        Button(action: {
            if camera.lastSavedThumbnail != nil {
                showThumbnailSheet = true
            }
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 54, height: 54)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )

                if let thumb = camera.lastSavedThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .accessibilityLabel("Photos Library")
        .sheet(isPresented: $showThumbnailSheet) {
            if let thumb = camera.lastSavedThumbnail {
                VStack(spacing: 20) {
                    Text("Latest Saved 4K Video")
                        .font(.headline)
                        .padding(.top)

                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(16)
                        .padding()

                    Text("Saved directly to your iOS Photos app.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button("Done") {
                        showThumbnailSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom)
                }
            }
        }
    }

    // MARK: - Camera Switch Button
    private var switchCameraButton: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                flipDegrees += 180
            }
            camera.switchCamera()
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 58, height: 58)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )

                VStack(spacing: 2) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(flipDegrees))

                    Text(camera.currentPosition == .back ? "REAR" : "FRONT")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .accessibilityLabel("Switch Camera")
    }

    // MARK: - Permissions View
    private var permissionsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "video.badge.waveform.fill")
                .font(.system(size: 64))
                .foregroundColor(.red)

            Text("Camera & Photos Access")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(camera.permissionError ?? "This app requires Camera, Microphone, and Photos access to record 4K 60fps video and seamlessly save it to your Photos.")
                .font(.system(size: 15))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }) {
                Text("Open iOS Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
        }
        .padding()
    }

    // MARK: - Helper
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    ContentView()
}
