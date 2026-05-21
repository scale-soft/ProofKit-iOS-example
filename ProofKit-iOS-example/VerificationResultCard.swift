import SwiftUI

// MARK: - Verification result summary card (reused in Captures and Verify tabs)

struct VerificationResultCard: View {
    let json: String

    private var parsed: [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private var status:             String { parsed?["status"]             as? String ?? "unknown" }
    private var message:            String { parsed?["message"]            as? String ?? "" }
    private var isSignatureValid:   Bool   { parsed?["isSignatureValid"]   as? Bool ?? false }
    private var isHashMatch:        Bool   { parsed?["isHashMatch"]        as? Bool ?? false }
    private var isKeyRegistered:    Bool   { parsed?["isKeyRegistered"]    as? Bool ?? false }
    private var isDeviceAttested:   Bool   { parsed?["isDeviceAttested"]   as? Bool ?? false }
    private var isTimestampVerified:Bool   { parsed?["isTimestampVerified"] as? Bool ?? false }
    private var isLocationVerified: Bool   { parsed?["isLocationVerified"] as? Bool ?? false }
    private var fingerprint:        String { parsed?["publicKeyFingerprint"] as? String ?? "" }
    private var reasons:           [String] {
        parsed?["reasons"] as? [String] ?? []
    }

    private var statusColor: Color {
        switch status {
        case "fullyVerified":                   return .green
        case "partiallyVerified":               return .orange
        case "tampered", "unrecognizedSigner":  return .red
        default:                                return .secondary
        }
    }

    private var statusIcon: String {
        switch status {
        case "fullyVerified":       return "checkmark.shield.fill"
        case "partiallyVerified":   return "exclamationmark.shield.fill"
        case "tampered":            return "xmark.shield.fill"
        case "unrecognizedSigner":  return "questionmark.circle.fill"
        default:                    return "shield.slash.fill"
        }
    }

    private var statusLabel: String {
        switch status {
        case "fullyVerified":       return "Fully Verified"
        case "partiallyVerified":   return "Partially Verified"
        case "tampered":            return "Tampered"
        case "unrecognizedSigner":  return "Unknown Signer"
        case "noSignature":         return "No Signature"
        default:                    return status
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Status banner
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusLabel)
                        .font(.headline)
                        .foregroundStyle(statusColor)
                    if !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            // Checklist
            VStack(spacing: 6) {
                checkRow("Signature Valid",     isSignatureValid)
                checkRow("Content Hash Match",  isHashMatch)
                checkRow("Key Registered",      isKeyRegistered)
                checkRow("Device Attested",     isDeviceAttested)
                checkRow("Timestamp Verified",  isTimestampVerified)
                checkRow("Location Verified",   isLocationVerified)
            }

            // Key fingerprint
            if !fingerprint.isEmpty {
                HStack {
                    Image(systemName: "key.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(fingerprint)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .contextMenu {
                    Button("Copy Fingerprint") {
                        UIPasteboard.general.string = fingerprint
                    }
                }
            }

            // Reasons
            if !reasons.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Details")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(reasons, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundStyle(.secondary)
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func checkRow(_ label: String, _ value: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: value ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(value ? .green : .red)
                .font(.subheadline)
            Text(label)
                .font(.subheadline)
            Spacer()
        }
    }
}

// MARK: - JSON display card

struct JsonCard: View {
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
                .padding(12)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
