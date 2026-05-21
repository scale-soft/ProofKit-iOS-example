import UIKit
import ProofKit

// MARK: - Imperative camera presentation

/// Presents `ProofKitCameraViewController` directly at the UIKit level, bypassing
/// SwiftUI's `fullScreenCover` / `UIHostingController` wrapping.
///
/// UIKit queries the frontmost *presented* view controller for orientation support.
/// When the camera VC is presented directly it is that frontmost VC, so its
/// `.portrait`-only overrides are respected regardless of what the host app allows.
func presentProofKitCamera(
    config:    ProofKitCameraConfig,
    deviceId:  String,
    onCapture: @escaping (_ filePath: String, _ bundleJson: String, _ mediaType: String) -> Void,
    onError:   @escaping (_ error: Error) -> Void,
    onDismiss: @escaping () -> Void
) {
    guard
        let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
        let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
    else {
        onDismiss()
        return
    }
    var top = rootVC
    while let presented = top.presentedViewController { top = presented }

    let cameraVC = ProofKitSDK.makeCamera(config: config)
    let bridge   = CameraViewBridge(
        cameraVC:  cameraVC,
        onCapture: onCapture,
        onError:   onError,
        onDismiss: onDismiss
    )
    cameraVC.delegate = bridge
    cameraVC.updateDeviceId(deviceId)

    // Keep bridge alive for the lifetime of the camera VC.
    objc_setAssociatedObject(cameraVC, &CameraViewBridge.key, bridge, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

    top.present(cameraVC, animated: true)
}

// MARK: - ProofKitCameraDelegate bridge

final class CameraViewBridge: NSObject, ProofKitCameraDelegate {
    static var key = 0

    private weak var cameraVC: ProofKitCameraViewController?
    private let onCapture: (_ filePath: String, _ bundleJson: String, _ mediaType: String) -> Void
    private let onError:   (_ error: Error) -> Void
    private let onDismiss: () -> Void

    init(
        cameraVC:  ProofKitCameraViewController,
        onCapture: @escaping (_ filePath: String, _ bundleJson: String, _ mediaType: String) -> Void,
        onError:   @escaping (_ error: Error) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.cameraVC  = cameraVC
        self.onCapture = onCapture
        self.onError   = onError
        self.onDismiss = onDismiss
    }

    func proofKitCamera(_ view: ProofKitCameraView, didCapture filePath: String, bundleJson: String) {
        let mediaType = filePath.hasSuffix(".mp4") ? "video" : "photo"
        DispatchQueue.main.async { [self] in
            onCapture(filePath, bundleJson, mediaType)
            cameraVC?.dismiss(animated: true)
            onDismiss()
        }
    }

    func proofKitCamera(_ view: ProofKitCameraView, didFailWithError error: Error) {
        DispatchQueue.main.async { [self] in
            onError(error)
            cameraVC?.dismiss(animated: true)
            onDismiss()
        }
    }

    func proofKitCameraDidClose(_ view: ProofKitCameraView) {
        DispatchQueue.main.async { [self] in
            cameraVC?.dismiss(animated: true)
            onDismiss()
        }
    }

}
