import SwiftUI
import ProofKit

struct SetupView: View {
    @EnvironmentObject var appState: AppState

    @State private var showApiKey     = false
    @State private var alertTitle     = ""
    @State private var alertMessage   = ""
    @State private var showAlert      = false
    @State private var isBusy         = false

    var body: some View {
        NavigationStack {
            Form {
                // ── Brand header ─────────────────────────────────────────────
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(.blue)
                            Text("ProofKit SDK")
                                .font(.title2.bold())
                            Text("v\(ProofKitSDK.sdkVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 12)
                }

                // ── API key + base URL ────────────────────────────────────────
                Section {
                    HStack {
                        Group {
                            if showApiKey {
                                TextField("cpk_…", text: $appState.apiKey)
                            } else {
                                SecureField("cpk_…", text: $appState.apiKey)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))

                        Button {
                            showApiKey.toggle()
                        } label: {
                            Image(systemName: showApiKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        TextField("Base URL", text: $appState.baseUrl)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Button("Reset") {
                            appState.baseUrl = "https://proofkit.scalesoft.net/api/v1"
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Button {
                        if let error = appState.configure() {
                            alertTitle   = "Configuration Failed"
                            alertMessage = error
                            showAlert    = true
                        }
                    } label: {
                        Label(
                            appState.isConfigured ? "Reconfigure SDK" : "Configure SDK",
                            systemImage: appState.isConfigured
                                ? "checkmark.circle.fill"
                                : "gearshape.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.apiKey.isEmpty)
                } header: {
                    Text("API Configuration")
                } footer: {
                    if appState.isConfigured {
                        Label("SDK configured", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }

                // ── Device identity ───────────────────────────────────────────
                if appState.isConfigured {
                    Section {
                        if !appState.publicKeyHex.isEmpty {
                            identityRow(
                                label: "Public Key",
                                value: String(appState.publicKeyHex.prefix(23)) + "…",
                                copyValue: appState.publicKeyHex
                            )
                        }
                        if !appState.deviceId.isEmpty {
                            identityRow(
                                label: "Device ID",
                                value: String(appState.deviceId.prefix(18)) + "…",
                                copyValue: appState.deviceId
                            )
                        }

                        LabeledContent("Pending Telemetry") {
                            Text("\(appState.pendingTelemetry) captures")
                                .foregroundStyle(appState.pendingTelemetry > 0 ? .orange : .secondary)
                        }

                        Button {
                            appState.refreshIdentity()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    } header: {
                        Text("Device Identity")
                    }

                    // ── Registration ──────────────────────────────────────────
                    Section {
                        actionRow(
                            title: appState.deviceId.isEmpty ? "Register Device" : "Re-register",
                            icon:  "iphone.badge.plus"
                        ) {
                            await runAction("Registration") {
                                try await appState.registerDevice()
                            }
                        }

                        if !appState.registrationJson.isEmpty {
                            DisclosureGroup("Registration Response") {
                                JsonViewer(json: appState.registrationJson)
                            }
                        }

                        actionRow(title: "Issue Certificate", icon: "doc.badge.plus") {
                            await runAction("Certificate") {
                                try await appState.issueCertificate()
                            }
                        }

                        if !appState.certificateJson.isEmpty {
                            DisclosureGroup("Certificate Response") {
                                JsonViewer(json: appState.certificateJson)
                            }
                        }
                    } header: {
                        Text("Device Registration")
                    } footer: {
                        Text("Register once per device. Issue a certificate after successful registration.")
                    }
                }
            }
            .navigationTitle("ProofKit Demo")
            .navigationBarTitleDisplayMode(.inline)
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    // MARK: Helpers

    private func identityRow(label: String, value: String, copyValue: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Copy") { UIPasteboard.general.string = copyValue }
        }
    }

    private func actionRow(
        title: String,
        icon:  String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: icon)
                }
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .disabled(isBusy)
    }

    private func runAction(_ name: String, work: () async throws -> String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await work()
            alertTitle   = "\(name) Successful"
            alertMessage = "Operation completed. See the response below."
        } catch {
            alertTitle   = "\(name) Failed"
            alertMessage = error.localizedDescription
        }
        showAlert = true
    }
}

// MARK: - Shared helpers

struct JsonViewer: View {
    let json: String

    var pretty: String {
        guard
            let data   = json.data(using: .utf8),
            let obj    = try? JSONSerialization.jsonObject(with: data),
            let out    = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
            let result = String(data: out, encoding: .utf8)
        else { return json }
        return result
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(pretty)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.vertical, 4)
        }
    }
}
