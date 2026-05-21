import Foundation
import Combine
import UIKit
import ProofKit

// MARK: - CaptureRecord

struct CaptureRecord: Identifiable, Codable {
    let id: UUID
    let filePath: String
    let bundleJson: String
    let capturedAt: Date
    let mediaType: String   // "photo" | "video"
    var verificationJson: String?

    init(filePath: String, bundleJson: String, mediaType: String) {
        self.id            = UUID()
        self.filePath      = filePath
        self.bundleJson    = bundleJson
        self.capturedAt    = Date()
        self.mediaType     = mediaType
        self.verificationJson = nil
    }

    // Resolves the stored path against the current app container's Documents directory.
    // New records store a Documents-relative path (e.g. "media/photo_123.jpg") so the
    // path stays valid across reinstalls when the container UUID rotates.
    // Legacy records with an absolute path are handled by re-rooting their last two
    // path components (subdir + filename) under the current Documents directory.
    var resolvedFilePath: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if filePath.hasPrefix("/") {
            // Legacy absolute path — re-root under current Documents/media/
            let filename = URL(fileURLWithPath: filePath).lastPathComponent
            return docs.appendingPathComponent("media").appendingPathComponent(filename).path
        }
        return docs.appendingPathComponent(filePath).path
    }

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: resolvedFilePath)
    }

    var thumbnail: UIImage? {
        guard mediaType == "photo", fileExists else { return nil }
        return UIImage(contentsOfFile: resolvedFilePath)
    }

    var parsedBundle: [String: Any]? {
        guard let data = bundleJson.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {

    // Persisted config
    @Published var apiKey: String
    @Published var baseUrl: String

    // SDK status
    @Published var isConfigured   = false
    @Published var publicKeyHex   = ""
    @Published var deviceId       = ""
    @Published var pendingTelemetry = 0

    // Registration results
    @Published var registrationJson  = ""
    @Published var certificateJson   = ""

    // Captures
    @Published var captures: [CaptureRecord] = []

    // Busy flag for async actions
    @Published var isBusy = false

    // MARK: Keys
    private static let apiKeyKey   = "demo_api_key"
    private static let baseUrlKey  = "demo_base_url"
    private static let capturesKey = "demo_captures"

    init() {
        apiKey  = UserDefaults.standard.string(forKey: Self.apiKeyKey) ?? ""
        baseUrl = UserDefaults.standard.string(forKey: Self.baseUrlKey)
                  ?? "https://proofkit.scalesoft.net/api/v1"
        loadCaptures()

        // Auto-configure with saved key on launch
        if !apiKey.isEmpty {
            _ = ProofKitSDK.configure(apiKey: apiKey, baseUrl: baseUrl)
            isConfigured = true
            refreshIdentity()
        }
    }

    // MARK: Configure

    /// Returns nil on success, error string on failure.
    func configure() -> String? {
        let error = ProofKitSDK.configure(apiKey: apiKey, baseUrl: baseUrl)
        guard error == nil else { return error }
        isConfigured = true
        UserDefaults.standard.set(apiKey,   forKey: Self.apiKeyKey)
        UserDefaults.standard.set(baseUrl,  forKey: Self.baseUrlKey)
        refreshIdentity()
        return nil
    }

    func refreshIdentity() {
        if let data = try? ProofKitSDK.getPublicKey() {
            publicKeyHex = data.map { String(format: "%02x", $0) }.joined(separator: ":")
        }
        deviceId        = ProofKitSDK.deviceId ?? ""
        pendingTelemetry = ProofKitSDK.pendingTelemetryCount()
    }

    // MARK: Device registration

    func registerDevice() async throws -> String {
        isBusy = true
        defer { isBusy = false }
        let json = try await ProofKitSDK.registerDevice()
        registrationJson = json
        deviceId = ProofKitSDK.deviceId ?? ""
        return json
    }

    func issueCertificate() async throws -> String {
        isBusy = true
        defer { isBusy = false }
        let json = try await ProofKitSDK.issueCertificate()
        certificateJson = json
        return json
    }

    // MARK: Captures

    func addCapture(filePath: String, bundleJson: String, mediaType: String) {
        // Store the path relative to Documents so it survives reinstalls (container UUID changes).
        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        let relative: String
        if filePath.hasPrefix(docsPath) {
            relative = String(filePath.dropFirst(docsPath.count).drop(while: { $0 == "/" }))
        } else {
            relative = URL(fileURLWithPath: filePath).lastPathComponent
        }
        captures.insert(
            CaptureRecord(filePath: relative, bundleJson: bundleJson, mediaType: mediaType),
            at: 0
        )
        saveCaptures()
    }

    func updateVerification(id: UUID, json: String) {
        guard let idx = captures.firstIndex(where: { $0.id == id }) else { return }
        captures[idx].verificationJson = json
        saveCaptures()
    }

    func deleteCapture(id: UUID) {
        guard let idx = captures.firstIndex(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(atPath: captures[idx].resolvedFilePath)
        captures.remove(at: idx)
        saveCaptures()
    }

    // MARK: Persistence

    private func saveCaptures() {
        if let data = try? JSONEncoder().encode(captures) {
            UserDefaults.standard.set(data, forKey: Self.capturesKey)
        }
    }

    private func loadCaptures() {
        guard
            let data    = UserDefaults.standard.data(forKey: Self.capturesKey),
            let records = try? JSONDecoder().decode([CaptureRecord].self, from: data)
        else { return }
        captures = records
    }
}
