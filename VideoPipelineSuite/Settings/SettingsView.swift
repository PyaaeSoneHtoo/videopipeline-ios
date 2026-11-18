import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var session: UserSession
    @State private var copiedToast: Bool = false

    private var activeDeviceId: String {
        session.deviceId.isEmpty ? DeviceFingerprint.getDeviceId() : session.deviceId
    }

    var body: some View {
        ZStack {
            AppTheme.bgDark.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Account Info Card
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Account & License", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.headline)
                            .foregroundColor(AppTheme.primaryLight)

                        infoRow(title: "Email", value: session.email.isEmpty ? "user@example.com" : session.email)
                        Divider().background(AppTheme.surfaceCardBorder)
                        infoRow(title: "Plan", value: session.plan)
                        Divider().background(AppTheme.surfaceCardBorder)
                        infoRow(title: "Valid Until", value: "\(session.expiresAt) (Active)", valueColor: AppTheme.emerald)
                    }
                    .pipelineCard()

                    // Hardware Device Binding Card
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Hardware Device Slot", systemImage: "iphone.gen3")
                            .font(.headline)
                            .foregroundColor(AppTheme.cyan)

                        Text(activeDeviceId)
                            .font(.callout.monospaced().bold())
                            .foregroundColor(AppTheme.textPrimary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.surfaceCardElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button {
                            UIPasteboard.general.string = activeDeviceId
                            copiedToast = true
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                copiedToast = false
                            }
                        } label: {
                            Label(copiedToast ? "Copied to Clipboard!" : "Copy Device ID", systemImage: copiedToast ? "checkmark" : "doc.on.doc")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(AppTheme.primary.opacity(0.2))
                                .foregroundColor(AppTheme.primaryLight)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .pipelineCard()

                    // API Keys & Telegram Login Entry
                    NavigationLink(destination: ApiSetupView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "key.horizontal.fill")
                                .font(.title3)
                                .foregroundColor(AppTheme.emerald)
                                .frame(width: 40, height: 40)
                                .background(AppTheme.emerald.opacity(0.16))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("API Keys & Telegram Login")
                                    .font(.headline)
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("Import .env/JSON, Gemini, DeepSeek & Telegram Bot/MTProto")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .pipelineCard(cornerRadius: 16, padding: 14)
                    }

                    // Storage Info Card
                    VStack(alignment: .leading, spacing: 8) {
                        Label("iOS Files Integration", systemImage: "folder.badge.gearshape")
                            .font(.headline)
                            .foregroundColor(AppTheme.amber)
                        Text("All trimmed videos and downloaded files are stored locally in Apple's Files app under: On My iPhone → Video Pipeline.")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pipelineCard()

                    // Sign Out
                    Button {
                        session.clear()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: AppTheme.danger))
                    .padding(.top, 8)
                }
                .padding(16)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(title: String, value: String, valueColor: Color = AppTheme.textPrimary) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}
