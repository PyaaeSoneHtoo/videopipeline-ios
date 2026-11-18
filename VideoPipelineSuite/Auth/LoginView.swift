import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: UserSession
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    private let deviceId = DeviceFingerprint.getDeviceId()

    var body: some View {
        ZStack {
            AppTheme.bgDark.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 36)

                    // Logo & Header
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22)
                                .fill(AppTheme.primary.opacity(0.16))
                                .frame(width: 82, height: 82)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22)
                                        .stroke(AppTheme.primary.opacity(0.5), lineWidth: 1.5)
                                )
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 38))
                                .foregroundColor(AppTheme.primaryLight)
                        }

                        Text("Video Pipeline Suite")
                            .font(.title.bold())
                            .foregroundColor(AppTheme.textPrimary)

                        Text("iOS Mobile Automation Studio")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    // Login Form Card
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Account Email")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppTheme.textSecondary)

                            TextField("name@example.com", text: $email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(AppTheme.surfaceCardElevated)
                                .foregroundColor(AppTheme.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(AppTheme.surfaceCardBorder, lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppTheme.textSecondary)

                            SecureField("Enter your license password", text: $password)
                                .padding(14)
                                .background(AppTheme.surfaceCardElevated)
                                .foregroundColor(AppTheme.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(AppTheme.surfaceCardBorder, lineWidth: 1)
                                )
                        }

                        if let error = errorMessage {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(AppTheme.danger)
                                Text(error)
                                    .font(.footnote)
                                    .foregroundColor(AppTheme.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(AppTheme.danger.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Button {
                            performLogin()
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Sign In & Activate License")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isLoading)
                    }
                    .pipelineCard()

                    // Device Fingerprint Badge
                    VStack(spacing: 6) {
                        Text("Hardware Device ID")
                            .font(.caption)
                            .foregroundColor(AppTheme.textMuted)
                        Text(deviceId)
                            .font(.caption.monospaced())
                            .foregroundColor(AppTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppTheme.surfaceCard)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(AppTheme.surfaceCardBorder, lineWidth: 1))
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func performLogin() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPass = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty, !trimmedPass.isEmpty else {
            errorMessage = "Please enter both email and password."
            return
        }

        errorMessage = nil
        isLoading = true

        Task {
            let result = await AuthService.signIn(email: trimmedEmail, password: trimmedPass, deviceId: deviceId)
            isLoading = false
            if result.success {
                session.saveLogin(
                    token: result.token ?? "",
                    uid: result.uid ?? "",
                    emailAddress: result.email ?? trimmedEmail,
                    expiry: result.expiresAt ?? "2026-12-31",
                    device: result.boundDeviceId ?? deviceId,
                    userPlan: result.plan
                )
            } else {
                errorMessage = result.errorMessage ?? "Login failed. Please try again."
            }
        }
    }
}
