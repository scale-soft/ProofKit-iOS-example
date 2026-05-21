import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ProofKit

struct VerifyView: View {
    @EnvironmentObject var appState: AppState

    @State private var photosPickerItem:  PhotosPickerItem?
    @State private var importedFilePath:  String?
    @State private var importedImage:     UIImage?
    @State private var verificationJson:  String = ""
    @State private var isVerifying        = false
    @State private var errorMessage       = ""
    @State private var showError          = false
    @State private var showFilePicker     = false
    @State private var metadataJson:      String = ""
    @State private var showMetadataSheet  = false

    var body: some View {
        NavigationStack {
            Form {
                if !appState.isConfigured {
                    Section {
                        Label(
                            "Configure the SDK in the Setup tab first.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                // ── Source picker ─────────────────────────────────────────────
                Section {
                    PhotosPicker(
                        selection: $photosPickerItem,
                        matching: .images
                    ) {
                        Label("Pick Photo from Library", systemImage: "photo.on.rectangle")
                    }
                    .onChange(of: photosPickerItem) { _, item in
                        Task { await loadPhotoPickerItem(item) }
                    }

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Import from Files", systemImage: "doc.badge.plus")
                    }
                } header: {
                    Text("Source File")
                } footer: {
                    if let path = importedFilePath {
                        Text(path.components(separatedBy: "/").last ?? path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // ── Preview ───────────────────────────────────────────────────
                if let img = importedImage {
                    Section {
                        HStack {
                            Spacer()
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Spacer()
                        }
                    }
                }

                // ── Actions ───────────────────────────────────────────────────
                if importedFilePath != nil {
                    Section {
                        Button {
                            Task { await runVerify() }
                        } label: {
                            HStack {
                                if isVerifying {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "checkmark.shield.fill")
                                }
                                Text(isVerifying ? "Verifying…" : "Verify Authenticity")
                                    .bold()
                                Spacer()
                            }
                        }
                        .disabled(isVerifying || !appState.isConfigured)

                        Button {
                            extractMetadata()
                        } label: {
                            Label("Extract Metadata Only", systemImage: "doc.text.magnifyingglass")
                        }
                        .disabled(!appState.isConfigured)
                    }
                }

                // ── Verification result ───────────────────────────────────────
                if !verificationJson.isEmpty {
                    Section {
                        VerificationResultCard(json: verificationJson)
                    } header: {
                        Text("Verification Result")
                    }

                    Section {
                        JsonCard(json: verificationJson)
                    } header: {
                        Text("Raw JSON")
                    }
                }
            }
            .navigationTitle("Verify")
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.jpeg, .png, .movie, .mpeg4Movie, UTType(filenameExtension: "heic") ?? .image],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    importFile(url: url)
                }
            }
            .alert("Verification Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showMetadataSheet) {
                NavigationStack {
                    ScrollView {
                        JsonCard(json: metadataJson.isEmpty ? "{}" : metadataJson)
                            .padding()
                    }
                    .navigationTitle("Embedded Metadata")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showMetadataSheet = false }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadPhotoPickerItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let path = docs.appendingPathComponent("import_verify.jpg").path
        try? data.write(to: URL(fileURLWithPath: path))
        importedFilePath = path
        importedImage    = UIImage(data: data)
        verificationJson = ""
    }

    private func importFile(url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dest = docs.appendingPathComponent("import_verify.\(url.pathExtension)").path
        try? FileManager.default.removeItem(atPath: dest)
        try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: dest))
        importedFilePath = dest
        importedImage    = UIImage(contentsOfFile: dest)
        verificationJson = ""
    }

    private func runVerify() async {
        guard let path = importedFilePath else { return }
        isVerifying = true
        defer { isVerifying = false }
        do {
            verificationJson = try await ProofKitSDK.verify(filePath: path)
        } catch {
            errorMessage = error.localizedDescription
            showError    = true
        }
    }

    private func extractMetadata() {
        guard let path = importedFilePath else { return }
        do {
            metadataJson     = (try ProofKitSDK.extractMetadata(filePath: path)) ?? "{}"
            showMetadataSheet = true
        } catch {
            errorMessage = error.localizedDescription
            showError    = true
        }
    }
}
