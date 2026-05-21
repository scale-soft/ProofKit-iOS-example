import SwiftUI
import ProofKit

struct CameraTabView: View {
    @EnvironmentObject var appState: AppState

    @State private var config        = ProofKitCameraConfig()
    @State private var extraInset    = 0.0
    @State private var showCamera    = false
    @State private var lastJson      = ""
    @State private var errorMessage  = ""
    @State private var showError     = false

    var body: some View {
        NavigationStack {
            Form {
                // ── Not configured warning ────────────────────────────────────
                if !appState.isConfigured {
                    Section {
                        Label(
                            "Go to Setup and configure the SDK with your API key first.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                // ── Camera parameters ─────────────────────────────────────────
                Section {
                    Picker("Quality", selection: $config.quality) {
                        Text("MAX").tag("max")
                        Text("1080p").tag("veryHigh")
                        Text("720p").tag("high")
                    }
                    .pickerStyle(.segmented)

                    Toggle("Include GPS Location", isOn: $config.includeLocation)
                    Toggle("Allow Video Recording", isOn: $config.allowVideo)
                    Toggle("Allow Quality Change", isOn: $config.allowQualityChange)
                    Toggle("Show Close Button",    isOn: $config.showCloseButton)

                    HStack {
                        Text("Extra Bottom Inset")
                        Spacer()
                        Stepper(
                            "\(Int(extraInset)) pt",
                            value:  $extraInset,
                            in:     0...200,
                            step:   50
                        )
                        .onChange(of: extraInset) { _, new in
                            config.extraBottomInset = new
                        }
                    }
                } header: {
                    Text("Camera Configuration")
                } footer: {
                    Text("These values are passed to ProofKitSDK.makeCamera(config:) on each launch.")
                }

                // ── Launch ────────────────────────────────────────────────────
                Section {
                    Button {
                        guard !showCamera else { return }
                        showCamera = true
                        presentProofKitCamera(
                            config:   config,
                            deviceId: appState.deviceId,
                            onCapture: { filePath, bundleJson, mediaType in
                                lastJson = bundleJson
                                appState.addCapture(
                                    filePath:   filePath,
                                    bundleJson: bundleJson,
                                    mediaType:  mediaType
                                )
                                showCamera = false
                            },
                            onError: { error in
                                errorMessage = error.localizedDescription
                                showError    = true
                                showCamera   = false
                            },
                            onDismiss: {
                                showCamera = false
                            }
                        )
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "camera.fill")
                            Text("Open Camera")
                                .bold()
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!appState.isConfigured || showCamera)
                }

                // ── Last capture preview ──────────────────────────────────────
                if !lastJson.isEmpty, let record = appState.captures.first {
                    Section {
                        HStack(spacing: 12) {
                            if let img = record.thumbnail {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "video.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 64, height: 64)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Signed & saved", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.subheadline.bold())
                                Text(record.capturedAt, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(record.filePath.components(separatedBy: "/").last ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }

                        DisclosureGroup("Signature Bundle JSON") {
                            JsonViewer(json: lastJson)
                        }
                    } header: {
                        Text("Last Capture")
                    }
                }
            }
            .navigationTitle("Camera")
            .alert("Camera Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
}
