import SmartTubeIOSCore
import SwiftUI

// MARK: - Parental Controls

struct ParentalControlsSettingsSection: View {
    @Environment(SettingsStore.self) private var store
    @State private var mode: ParentalControlsMode?

    var body: some View {
        Section {
            if store.settings.settingsPINHash == nil {
                Button("Set PIN") { mode = .set }
                    .accessibilityIdentifier(AccessibilityID.Settings.setPINButton)
            } else {
                Button("Change PIN") { mode = .change }
                    .accessibilityIdentifier(AccessibilityID.Settings.changePINButton)
                Button("Remove PIN", role: .destructive) { mode = .remove }
                    .accessibilityIdentifier(AccessibilityID.Settings.removePINButton)
            }
        } header: {
            Text("Parental Controls")
        } footer: {
            Text("With a PIN set, it's asked for every time Settings opens.")
        }
        .sheet(item: $mode) { mode in
            ParentalControlsSheet(mode: mode)
        }
    }
}

// MARK: - About

struct AboutSettingsSection: View {
    @Environment(SettingsStore.self) private var store
    @State private var reportSaved = false
    @State private var confirmReset = false
    #if os(tvOS)
    @State private var showGitHubQR = false
    #endif

    private static let gitHubURL = URL(string: "https://github.com/milika/SmartTubeIOS")!  // a valid literal

    var body: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            #if os(tvOS)
            Button {
                showGitHubQR = true
            } label: {
                Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            #else
            Link(destination: Self.gitHubURL) {
                Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            #endif
            Button {
                DiagnosticsLogger.sendDiagnosticReport()
                reportSaved = true
            } label: {
                if reportSaved {
                    Label("Report Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("Save Diagnostic Report", systemImage: "ladybug")
                }
            }
            .disabled(reportSaved || store.settings.disableAnalytics)
            .accessibilityIdentifier(AccessibilityID.Settings.sendDiagnosticReportButton)
            Button("Reset All Settings", role: .destructive) { confirmReset = true }
                .accessibilityIdentifier(AccessibilityID.Settings.resetAllButton)
        }
        .alert("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Every setting goes back to its default, including the Settings PIN. Accounts and watch history are kept."
            )
        }
        #if os(tvOS)
        .sheet(isPresented: $showGitHubQR) {
            GitHubQRView(url: Self.gitHubURL)
        }
        #endif
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Experimental (macOS)

#if os(macOS)
struct ExperimentalSettingsSection: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Section {
            Toggle("IFrame Player (TOS-compliant, shows ads)", isOn: $store.settings.useTOSPlayerOnMac)
                .accessibilityIdentifier(AccessibilityID.Settings.useTOSPlayerOnMacToggle)
        } header: {
            Text("Experimental")
        } footer: {
            Text(
                "Uses YouTube's official embedded player instead of the direct stream pipeline. Quality selection is "
                    + "unavailable and ads play. Useful for videos that refuse to play the standard way.")
        }
    }
}
#endif

// MARK: - GitHubQRView (tvOS)

#if os(tvOS)
private struct GitHubQRView: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)

                    Text("SmartTube on GitHub")
                        .font(.largeTitle).fontWeight(.bold)

                    Text("Scan the QR code with your phone to view the project on GitHub.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                QRCodeView(content: url.absoluteString)
                    .frame(width: 280, height: 280)
                    .padding(16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Text(url.absoluteString)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
                    .font(.headline)
            }
            .padding(40)
        }
    }
}
#endif
