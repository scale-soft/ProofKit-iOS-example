import SwiftUI
import ProofKit

struct CapturesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                if appState.captures.isEmpty {
                    ContentUnavailableView(
                        "No Captures Yet",
                        systemImage: "camera.badge.clock",
                        description: Text("Signed photos and videos appear here after you use the Camera tab.")
                    )
                } else {
                    List {
                        ForEach(appState.captures) { record in
                            NavigationLink {
                                CaptureDetailView(record: record)
                            } label: {
                                CaptureRow(record: record)
                            }
                        }
                        .onDelete { offsets in
                            for idx in offsets {
                                appState.deleteCapture(id: appState.captures[idx].id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Captures")
            .toolbar {
                if !appState.captures.isEmpty {
                    EditButton()
                }
            }
        }
    }
}

// MARK: - Row

struct CaptureRow: View {
    let record: CaptureRecord

    var verificationStatus: String? {
        guard let json = record.verificationJson,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return dict["status"] as? String
    }

    var statusColor: Color {
        switch verificationStatus {
        case "fullyVerified":        return .green
        case "partiallyVerified":    return .orange
        case "tampered",
             "unrecognizedSigner":   return .red
        default:                     return .secondary
        }
    }

    var statusIcon: String {
        switch verificationStatus {
        case "fullyVerified":        return "checkmark.shield.fill"
        case "partiallyVerified":    return "exclamationmark.shield.fill"
        case "tampered":             return "xmark.shield.fill"
        case "unrecognizedSigner":   return "questionmark.circle.fill"
        default:                     return "shield"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let img = record.thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "video.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.secondarySystemBackground))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(record.mediaType.capitalized)
                        .font(.subheadline.bold())
                    Spacer()
                    if verificationStatus != nil {
                        Image(systemName: statusIcon)
                            .foregroundStyle(statusColor)
                            .font(.caption)
                    }
                }
                Text(record.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.filePath.components(separatedBy: "/").last ?? "")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                if !record.fileExists {
                    Label("File missing", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail

struct CaptureDetailView: View {
    @EnvironmentObject var appState: AppState
    let record: CaptureRecord

    @State private var verificationJson = ""
    @State private var isVerifying      = false
    @State private var verifyError      = ""
    @State private var showError        = false

    var currentRecord: CaptureRecord? {
        appState.captures.first { $0.id == record.id }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // ── Media preview ─────────────────────────────────────────────
                mediaPreview

                // ── Capture metadata ──────────────────────────────────────────
                metadataCard

                // ── Verify button ─────────────────────────────────────────────
                Button {
                    Task { await verify() }
                } label: {
                    HStack {
                        if isVerifying {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.shield")
                        }
                        Text(isVerifying ? "Verifying…" : "Verify Authenticity")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isVerifying || !record.fileExists)
                .padding(.horizontal)

                // ── Verification result ───────────────────────────────────────
                let verJson = currentRecord?.verificationJson ?? verificationJson
                if !verJson.isEmpty {
                    VerificationResultCard(json: verJson)
                        .padding(.horizontal)
                }

                // ── Bundle JSON ───────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    Text("Signature Bundle")
                        .font(.headline)
                        .padding(.horizontal)
                    JsonCard(json: record.bundleJson)
                        .padding(.horizontal)
                }
                .padding(.bottom)
            }
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Verification Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verifyError)
        }
    }

    // MARK: Sub-views

    @ViewBuilder
    private var mediaPreview: some View {
        if let img = record.thumbnail {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 160)
                VStack(spacing: 8) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Video")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    private var metadataCard: some View {
        VStack(spacing: 0) {
            metaRow("Type",     record.mediaType.capitalized)
            Divider().padding(.leading)
            metaRow("Captured", record.capturedAt.formatted(date: .abbreviated, time: .shortened))
            Divider().padding(.leading)
            metaRow("File",     record.filePath.components(separatedBy: "/").last ?? "")
            Divider().padding(.leading)
            metaRow("Exists",   record.fileExists ? "Yes" : "No — file deleted")
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Actions

    private func verify() async {
        guard record.fileExists else { return }
        isVerifying = true
        defer { isVerifying = false }
        do {
            let json = try await ProofKitSDK.verify(filePath: record.resolvedFilePath)
            verificationJson = json
            appState.updateVerification(id: record.id, json: json)
        } catch {
            verifyError = error.localizedDescription
            showError   = true
        }
    }
}
