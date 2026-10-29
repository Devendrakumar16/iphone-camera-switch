# iPhone Camera Switch 📸

A high-performance iOS camera app built with **SwiftUI** and **AVFoundation**, supporting seamless front/back camera toggling, 4K 60FPS video capture, Dual Camera recording, tap-to-focus/expose, and direct export to Apple Photos.

---

## ✨ Features

- **Seamless Camera Switching**: Switch between Ultra Wide / Wide Rear and Front TrueDepth cameras with smooth 3D flip transitions.
- **4K @ 60 FPS Video Recording**: Low-latency video pipeline configured for highest available resolution and frame rates using `AVCaptureSession`.
- **Dual Camera Mode**: Concurrent multi-camera capture for simultaneous wide and selfie preview and recording.
- **Interactive Tap-to-Focus & Exposure**: Tap anywhere on the viewfinder to adjust focus and exposure dynamically with visual target boxes.
- **Torch & Flash Control**: Toggle torch on compatible rear camera sensors.
- **Direct Photos Library Export**: Automatic saving of recorded videos directly into the iOS Photos library with thumbnail generation and instant preview.
- **Modern Glassmorphic UI**: Built with native SwiftUI, featuring blur effects, live recording duration timer, and dynamic indicators.

---

## 🏗️ Architecture

```
iphone camera switch/
├── ContentView.swift        # Main SwiftUI user interface and gestures
├── CameraManager.swift      # ObservableObject coordinator & CaptureEngine
├── CameraPreviewView.swift  # UIViewRepresentable wrapping AVCaptureVideoPreviewLayer
└── iphone_camera_switchApp.swift
```

- **`CameraManager`**: Coordinates permissions, timer state, UI status, and interfaces with the underlying capture engine.
- **`CaptureEngine`**: Manages `AVCaptureSession`, `AVCaptureDeviceInput`, `AVCaptureVideoDataOutput`, and `AVAssetWriter`.
- **`CameraPreviewView`**: Handles real-time video rendering via `AVCaptureVideoPreviewLayer` and touch coordinate conversion for focus points.

---

## 📋 Requirements

- **iOS 16.0+**
- **Xcode 15.0+**
- **Swift 5.9+**
- **Physical Device**: Camera and microphone access require testing on a physical iPhone (simulator cannot provide hardware video input).

---

## 🔒 Permissions Required

The following privacy keys must be present in your target's `Info.plist`:

| Key | Description |
|---|---|
| `NSCameraUsageDescription` | Required to access camera feeds for preview and recording. |
| `NSMicrophoneUsageDescription` | Required to record audio alongside video. |
| `NSPhotoLibraryAddUsageDescription` | Required to save captured videos to Photos. |

---

## 🚀 Getting Started

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Devendrakumar16/iphone-camera-switch.git
   cd iphone-camera-switch
   ```

2. **Open in Xcode:**
   ```bash
   open "iphone camera switch.xcodeproj"
   ```

3. **Select your target device & Signing Team:**
   - Under `Signing & Capabilities`, select your Apple Developer team.
   - Connect your iPhone and set it as the run target.

4. **Build & Run (`⌘ + R`)**

---

## 👤 Author

- **Devendra Kumar** ([@Devendrakumar16](https://github.com/Devendrakumar16))
