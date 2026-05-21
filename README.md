# ProofKit iOS SDK

ProofKit is a native iOS SDK that lets any app capture photos and videos with a cryptographic proof of authenticity baked in at the moment of capture. Any third party can later verify that the file was not altered, was produced by a registered device, and carries a server-verified timestamp.

This repository contains both the SDK source and a runnable demo app (`ProofKit-iOS-example`) that exercises every SDK surface.

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
  - [Swift Package Manager](#swift-package-manager)
  - [CocoaPods](#cocoapods)
- [Info.plist permissions](#infoplist-permissions)
- [Quick start](#quick-start)
- [SDK reference](#sdk-reference)
  - [Configuration](#configuration)
  - [Device registration](#device-registration)
  - [Camera capture](#camera-capture)
  - [Signing a file](#signing-a-file)
  - [Verifying a file](#verifying-a-file)
  - [Extracting metadata](#extracting-metadata)
  - [Device identity](#device-identity)
  - [Diagnostics](#diagnostics)
  - [Error types](#error-types)
- [Demo app walkthrough](#demo-app-walkthrough)

---

## Requirements

- iOS 15.6+
- Xcode 14+
- Swift 5.7+
- A ProofKit API key (format: `cpk_…`) — obtain one from [scalesoft.net](https://scalesoft.net)

---

## Installation

### Swift Package Manager

Add the binary package to your project via Xcode:

1. **File → Add Package Dependencies…**
2. Enter the repository URL:
   ```
   https://github.com/scale-soft/ProofKit-dist
   ```
3. Select the version you want and add **ProofKit** to your app target.

Or add it to `Package.swift` manually:

```swift
dependencies: [
    .package(url: "https://github.com/scale-soft/ProofKit-dist", from: "1.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: ["ProofKit"])
]
```

### CocoaPods

```ruby
pod 'ProofKit', '~> 1.0'
```

Then run:

```bash
pod install
```

---

## Info.plist permissions

Add the following keys to your app's `Info.plist`. ProofKit will crash or silently fail at runtime without them.

| Key | When required |
|-----|--------------|
| `NSCameraUsageDescription` | Always — camera capture |
| `NSMicrophoneUsageDescription` | When `allowVideo = true` (default) |
| `NSLocationWhenInUseUsageDescription` | When `includeLocation = true` |
| `NSFaceIDUsageDescription` | Always — required for Face ID to appear when signing; without it iOS silently falls back to passcode |

---

## Quick start

```swift
import ProofKit

// 1. Configure once at app startup
ProofKitSDK.configure(apiKey: "cpk_your_key_here")

// 2. Register the device (first launch only)
// The certificate is issued automatically as part of registration.
try await ProofKitSDK.registerDevice()

// 3. Open the camera
let config = ProofKitCameraConfig()
let camera = ProofKitSDK.makeCamera(frame: view.bounds, config: config)
camera.delegate = self
view.addSubview(camera)
```

---

## SDK reference

### Configuration

```swift
@discardableResult
static func configure(
    apiKey: String,
    baseUrl: String = "https://proofkit.scalesoft.net/api/v1"
) -> String?
```

**Call once** before any other ProofKit API, typically in `application(_:didFinishLaunchingWithOptions:)` or at the top of your root SwiftUI `App`.

- `apiKey` — your `cpk_`-prefixed key. Returns an error string if the key is empty or has the wrong format; returns `nil` on success.
- `baseUrl` — override only if you run a private ProofKit backend.
- Triggers an async flush of any offline-queued telemetry in the background.

```swift
// UIKit
func application(_ app: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    if let error = ProofKitSDK.configure(apiKey: "cpk_...") {
        print("ProofKit config error:", error)
    }
    return true
}

// SwiftUI
@main
struct MyApp: App {
    init() {
        ProofKitSDK.configure(apiKey: "cpk_...")
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

**Optional parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `baseUrl` | `"https://proofkit.scalesoft.net/api/v1"` | Override only if using a private ProofKit backend |
| `certRenewalWindowDays` | `5` | Days before certificate expiry to trigger automatic background renewal. Set to `0` to disable. |

```swift
ProofKitSDK.configure(
    apiKey: "cpk_...",
    certRenewalWindowDays: 7   // renew cert 7 days before it expires
)
```

---

### Device registration

Every device must be registered with the ProofKit backend once before capture. The resulting device certificate is stored by the SDK and embedded in every `SignatureBundle` automatically.

#### `registerDevice()`

```swift
static func registerDevice() async throws -> String
```

Registers the device's Ed25519 public key with the backend. Returns a JSON string:

```json
{
  "deviceId": "550e8400-e29b-41d4-a716-446655440000",
  "keyFingerprint": "ab:cd:ef:...",
  "isNew": true,
  "certificate": { … }
}
```

Stores the `deviceId` **and** the device certificate in the Keychain automatically. You do **not** need to call `issueCertificate()` after registration — the server returns the certificate as part of the registration response.

**First-launch flow:**

```swift
func setupDevice() async {
    do {
        let json = try await ProofKitSDK.registerDevice()
        print("Registered:", json)
        // Certificate is already stored — ready to capture.
    } catch {
        print("Registration failed:", error.localizedDescription)
    }
}
```

#### `issueCertificate()`

```swift
static func issueCertificate() async throws -> String
```

Explicitly renews the server-signed device certificate. You normally **do not need to call this** — the SDK calls it automatically in the background when the certificate is within the renewal window configured in `configure(certRenewalWindowDays:)`.

Call it manually only if you want to force an immediate renewal (e.g. after detecting `certificate_status: "expired"` in a `SignatureBundle`).

---

### Camera capture

ProofKit provides a drop-in `UIView` subclass (`ProofKitCameraView`) that handles the full capture → signing pipeline. You never touch raw camera APIs.

#### `makeCamera(frame:config:)`

```swift
static func makeCamera(
    frame: CGRect = .zero,
    config: ProofKitCameraConfig = ProofKitCameraConfig()
) -> ProofKitCameraView
```

Creates a new camera session. Each call returns an independent view with its own `AVCaptureSession`.

**UIKit usage:**

```swift
let config = ProofKitCameraConfig()
config.includeLocation = true
config.allowVideo      = true

let camera = ProofKitSDK.makeCamera(frame: view.bounds, config: config)
camera.autoresizingMask = [.flexibleWidth, .flexibleHeight]
camera.delegate = self
view.addSubview(camera)
```

**SwiftUI usage** — wrap in a `UIViewControllerRepresentable` (see `CameraWrapperView.swift` in the demo):

```swift
struct CameraWrapperView: UIViewControllerRepresentable {
    let config: ProofKitCameraConfig
    @Binding var isPresented: Bool
    let onCapture: (String, String, String) -> Void   // filePath, bundleJson, mediaType

    func makeUIViewController(context: Context) -> CameraHostViewController {
        CameraHostViewController(config: config, coordinator: context.coordinator)
    }
    func updateUIViewController(_ vc: CameraHostViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
}
```

#### `ProofKitCameraConfig`

All properties have sensible defaults.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `quality` | `String` | `"max"` | Quality preset: `"max"` (device native), `"veryHigh"` (1080p), `"high"` (720p) |
| `includeLocation` | `Bool` | `false` | Embed GPS coordinate in the `SignatureBundle`. Requires location permission. |
| `allowVideo` | `Bool` | `true` | Show Photo/Video mode selector. Set to `false` for photo-only. |
| `allowQualityChange` | `Bool` | `true` | Let the user tap the quality badge to cycle presets. |
| `showCloseButton` | `Bool` | `false` | Show an X button; triggers `proofKitCameraDidClose(_:)`. |
| `extraBottomInset` | `CGFloat` | `0` | Extra space below the capture controls to clear a host-app tab bar. |

You can set properties individually or pass them directly to the initialiser:

```swift
// Initialiser (recommended)
let config = ProofKitCameraConfig(
    quality:          "veryHigh",   // 1080p
    includeLocation:  true,
    showCloseButton:  true,
    extraBottomInset: 83            // tab bar height
)

// Property-by-property (also valid)
var config = ProofKitCameraConfig()
config.quality          = "veryHigh"
config.includeLocation  = true
config.showCloseButton  = true
config.extraBottomInset = 83
```

**Android equivalent** — pass a `ProofKitCameraConfig` to `NativeCameraHandler.initialize`:

```kotlin
val config = ProofKitCameraConfig(
    quality         = "veryHigh",
    includeLocation = true,
    allowVideo      = true
)
cameraHandler.initialize(config, owner, onSuccess = { … }, onError = { … })
```

#### `ProofKitCameraDelegate`

Assign to `ProofKitCameraView.delegate` immediately after `makeCamera` returns.

```swift
public protocol ProofKitCameraDelegate: AnyObject {
    // Required
    func proofKitCamera(_ view: ProofKitCameraView, didCapture json: String)
    func proofKitCamera(_ view: ProofKitCameraView, didChangeOrientation isLandscape: Bool)

    // Optional (default no-op implementations provided)
    func proofKitCamera(_ view: ProofKitCameraView, didFailWithError error: Error)
    func proofKitCameraDidClose(_ view: ProofKitCameraView)
}
```

| Callback | When fired | Notes |
|----------|-----------|-------|
| `didCapture(json:)` | After capture + signing completes | `json` is the full `SignatureBundle` JSON |
| `didChangeOrientation(isLandscape:)` | On device rotation | Use to update any overlay UI |
| `didFailWithError(error:)` | On any camera or signing failure | Always implement to surface errors |
| `proofKitCameraDidClose(_:)` | User taps the close button | Only fires when `showCloseButton = true` |

```swift
extension MyViewController: ProofKitCameraDelegate {
    func proofKitCamera(_ view: ProofKitCameraView, didCapture json: String) {
        // json is the SignatureBundle — save it, send it to your server, or
        // pass the file path to ProofKitSDK.verify(filePath:)
        print("Captured:", json)
        dismiss(animated: true)
    }

    func proofKitCamera(_ view: ProofKitCameraView, didFailWithError error: Error) {
        showAlert(title: "Capture failed", message: error.localizedDescription)
    }

    func proofKitCameraDidClose(_ view: ProofKitCameraView) {
        dismiss(animated: true)
    }
}
```

#### `updateDeviceId(_:)`

```swift
camera.updateDeviceId(ProofKitSDK.deviceId ?? "")
```

Call this after device registration completes if the camera view is already on screen. The device ID is embedded in each `SignatureBundle`.

---

### Signing a file

```swift
static func sign(filePath: String) async throws -> String
```

Signs an existing file and returns the `SignatureBundle` JSON. Only PDF files are accepted; use the camera delegate for photos and videos.

```swift
let bundleJson = try await ProofKitSDK.sign(filePath: "/path/to/document.pdf")
```

The file is **not modified**. The bundle contains the SHA-256 hash of the original bytes; embed it alongside the document yourself if needed.

Throws `ProofKitError.unsupportedFileType` for non-PDF input, and `ProofKitError.notConfigured` if `configure()` was never called.

---

### Verifying a file

```swift
static func verify(filePath: String) async throws -> String
```

Runs the full verification pipeline on a signed media file and returns a JSON result string.

```swift
let resultJson = try await ProofKitSDK.verify(filePath: path)
```

**Pipeline steps:**
1. Extract embedded `SignatureBundle` from the file
2. Verify the Ed25519 signature
3. Re-hash the raw file content and compare with the stored hash
4. Look up the public key against the backend to confirm the device is registered
5. Verify the server-issued device certificate offline

**Result shape:**

```json
{
  "status":               "fullyVerified",
  "message":              "File is fully verified.",
  "reasons":              ["Signature valid", "Hash matches", "..."],
  "isSignatureValid":     true,
  "isHashMatch":          true,
  "isKeyRegistered":      true,
  "isDeviceAttested":     true,
  "isTimestampVerified":  true,
  "isLocationVerified":   false,
  "publicKeyFingerprint": "ab:cd:ef:01:23:45:67:89",
  "bundleJson":           "{...}"
}
```

**Status values:**

| Status | Meaning |
|--------|---------|
| `fullyVerified` | Signature valid + hash matches + device registered + platform attested |
| `partiallyVerified` | Signature valid and hash matches, but attestation unavailable |
| `unrecognizedSigner` | Signature valid but the key is not registered in the backend |
| `tampered` | Hash mismatch — file bytes changed after signing |
| `noSignature` | No ProofKit metadata found in the file |

---

### Extracting metadata

```swift
static func extractMetadata(filePath: String) throws -> String?
```

Extracts the raw `SignatureBundle` JSON embedded in a file **without** making any network requests. Returns `nil` if the file has no ProofKit metadata.

```swift
if let bundleJson = try ProofKitSDK.extractMetadata(filePath: path) {
    print("Embedded bundle:", bundleJson)
}
```

Useful for displaying provenance information instantly, before the full async `verify()` call completes.

---

### Device identity

#### `getPublicKey()`

```swift
static func getPublicKey() throws -> Data
```

Returns the raw 32-byte Ed25519 public key for this device, generating it if it does not exist. The private key never leaves the device Keychain.

```swift
let keyData = try ProofKitSDK.getPublicKey()
let hex = keyData.map { String(format: "%02x", $0) }.joined(separator: ":")
print("Public key:", hex)
```

#### `deviceId`

```swift
static var deviceId: String? { get }
```

The device ID assigned by the backend after `registerDevice()`. `nil` if the device has not been registered yet.

---

### Diagnostics

#### `pendingTelemetryCount()`

```swift
static func pendingTelemetryCount() -> Int
```

Returns the number of captures that were recorded while the device was offline and have not yet been flushed to the server. These are automatically flushed on the next `configure()` call.

```swift
let pending = ProofKitSDK.pendingTelemetryCount()
if pending > 0 {
    print("\(pending) offline capture(s) pending sync")
}
```

#### `sdkVersion`

```swift
static let sdkVersion: String   // e.g. "1.0.0"
```

---

### Error types

#### `ProofKitError`

Thrown by top-level `ProofKitSDK` methods.

| Case | Description |
|------|-------------|
| `.notConfigured` | `configure()` was not called before a signing or verification call |
| `.unsupportedFileType(String)` | `sign()` received a non-PDF file extension |

#### `ProofKitCameraError`

Delivered through `ProofKitCameraDelegate.didFailWithError(_:)`.

| Case | Description |
|------|-------------|
| `.captureFailed` | Photo capture pipeline failed with no system error |
| `.recordingFailed` | Video recording failed with no system error |

Other errors (camera setup failures, signing failures, network errors) are passed through as their underlying system or handler error types and are readable via `error.localizedDescription`.

---

## Demo app walkthrough

The `ProofKit-iOS-example` app has four tabs:

### Setup tab
- Enter your `cpk_…` API key and (optionally) a custom base URL
- Tap **Configure SDK** — this calls `ProofKitSDK.configure()`
- View the device's public key fingerprint and device ID once configured
- Register the device with **Register Device** and **Issue Certificate** — required before the first capture
- The registration and certificate responses are shown inline as formatted JSON

### Camera tab
- Configure all `ProofKitCameraConfig` options via live controls (quality, GPS, video, close button, extra inset)
- Tap **Open Camera** to launch the signed camera full-screen
- After capture, the signature bundle JSON is displayed beneath a thumbnail of the last capture

### Captures tab
- Lists every signed photo and video produced in this session
- Tap any row to open the detail view: media preview, file metadata, **Verify Authenticity** button, and the raw `SignatureBundle` JSON
- Swipe to delete removes the record and the file from disk

### Verify tab
- Pick any image from the photo library or import a file from Files
- Tap **Verify Authenticity** to run `ProofKitSDK.verify()` — shows a structured result card with per-step pass/fail indicators
- Tap **Extract Metadata Only** to run `ProofKitSDK.extractMetadata()` without a network call — shows the raw embedded bundle
