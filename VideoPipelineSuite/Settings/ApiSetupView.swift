import SwiftUI
import UniformTypeIdentifiers

struct ApiSetupView: View {
    @ObservedObject private var api = ApiSettingsStore.shared
    @ObservedObject private var mtproto = TelegramMTProtoManager.shared

    @State private var showEnvImporter: Bool = false
    @State private var importMessage: String? = nil

    @State private var otpCodeInput: String = ""
    @State private var twoFactorPasswordInput: String = ""

    @State private var geminiStatus: (ok: Bool, msg: String)? = nil
    @State private var isTestingGemini: Bool = false

    @State private var deepseekStatus: (ok: Bool, msg: String)? = nil
    @State private var isTestingDeepSeek: Bool = false

    @State private var showGeminiKey: Bool = false
    @State private var showDeepSeekKey: Bool = false

    var body: some View {
        ZStack {
            AppTheme.bgDark.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // 1. Native Telegram MTProto Login Card (Phone + OTP + 2FA)
                    telegramMTProtoCard

                    // 2. Quick .env / JSON Import Card
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Import PC Config (.env / JSON)", systemImage: "square.and.arrow.down.on.square")
                            .font(.headline)
                            .foregroundColor(AppTheme.emerald)
                        Text("Import your `.env` or `credentials.json` from PC Video Pipeline Suite to auto-fill MTProto API ID/Hash, Gemini, and DeepSeek keys in 1 tap.")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)

                        Button {
                            showEnvImporter = true
                        } label: {
                            Label("Import .env or JSON File from iOS Files", systemImage: "doc.badge.plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(AppTheme.emerald.opacity(0.18))
                                .foregroundColor(AppTheme.emerald)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(AppTheme.emerald.opacity(0.4), lineWidth: 1)
                                )
                        }

                        if let msg = importMessage {
                            Text(msg)
                                .font(.caption.weight(.medium))
                                .foregroundColor(AppTheme.cyan)
                        }
                    }
                    .pipelineCard()

                    // 3. Preferred AI Provider
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Default AI Provider", systemImage: "cpu.fill")
                            .font(.headline)
                            .foregroundColor(AppTheme.primaryLight)

                        Picker("AI Provider", selection: $api.preferredProvider) {
                            ForEach(AIProvider.allCases) { provider in
                                Text(provider.rawValue).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .pipelineCard()

                    // 4. Google Gemini API Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Google Gemini API", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundColor(AppTheme.primaryLight)
                            Spacer()
                            statusBadge(api.hasGeminiKey ? "Configured" : "Not Set", color: api.hasGeminiKey ? AppTheme.emerald : AppTheme.textMuted)
                        }

                        Text("Used for AI Video Ad Cutter & Gemini Batch Renamer.")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)

                        secretField(
                            placeholder: "Paste Gemini API Key (AIzaSy...)",
                            text: $api.geminiApiKey,
                            isRevealed: $showGeminiKey
                        )

                        HStack {
                            Text("Model")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Picker("Gemini Model", selection: $api.geminiModel) {
                                ForEach(ApiSettingsStore.geminiModels, id: \.id) { m in
                                    Text(m.label).tag(m.id)
                                }
                            }
                            .tint(AppTheme.primaryLight)
                        }

                        HStack(spacing: 10) {
                            Button {
                                isTestingGemini = true
                                geminiStatus = nil
                                Task {
                                    let res = await api.testGeminiKey()
                                    geminiStatus = (res.ok, res.message)
                                    isTestingGemini = false
                                }
                            } label: {
                                if isTestingGemini {
                                    ProgressView().tint(.white)
                                } else {
                                    Label("Verify Key", systemImage: "checkmark.shield")
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.primary)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .disabled(isTestingGemini)

                            Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                                Label("Get Free Key", systemImage: "arrow.up.right.square")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.surfaceCardElevated)
                                    .foregroundColor(AppTheme.primaryLight)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }

                        if let status = geminiStatus {
                            statusFeedback(ok: status.ok, message: status.msg)
                        }
                    }
                    .pipelineCard()

                    // 5. DeepSeek API Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("DeepSeek AI API", systemImage: "brain.head.profile")
                                .font(.headline)
                                .foregroundColor(AppTheme.cyan)
                            Spacer()
                            statusBadge(api.hasDeepSeekKey ? "Configured" : "Not Set", color: api.hasDeepSeekKey ? AppTheme.emerald : AppTheme.textMuted)
                        }

                        Text("Supports DeepSeek Chat & DeepSeek Vision for ad detection and series renaming.")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)

                        secretField(
                            placeholder: "Paste DeepSeek API Key (sk-...)",
                            text: $api.deepseekApiKey,
                            isRevealed: $showDeepSeekKey
                        )

                        HStack {
                            Text("Model")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Picker("DeepSeek Model", selection: $api.deepseekModel) {
                                ForEach(ApiSettingsStore.deepseekModels, id: \.id) { m in
                                    Text(m.label).tag(m.id)
                                }
                            }
                            .tint(AppTheme.cyan)
                        }

                        HStack(spacing: 10) {
                            Button {
                                isTestingDeepSeek = true
                                deepseekStatus = nil
                                Task {
                                    let res = await api.testDeepSeekKey()
                                    deepseekStatus = (res.ok, res.message)
                                    isTestingDeepSeek = false
                                }
                            } label: {
                                if isTestingDeepSeek {
                                    ProgressView().tint(.white)
                                } else {
                                    Label("Verify Key", systemImage: "checkmark.shield")
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.cyan)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .disabled(isTestingDeepSeek)

                            Link(destination: URL(string: "https://platform.deepseek.com/api_keys")!) {
                                Label("Get Key", systemImage: "arrow.up.right.square")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.surfaceCardElevated)
                                    .foregroundColor(AppTheme.cyan)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }

                        if let status = deepseekStatus {
                            statusFeedback(ok: status.ok, message: status.msg)
                        }
                    }
                    .pipelineCard()
                }
                .padding(16)
            }
        }
        .navigationTitle("MTProto & API Setup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showEnvImporter,
            allowedContentTypes: [.plainText, .json, .data, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    let res = api.importConfig(from: text)
                    importMessage = res.summary
                } else {
                    importMessage = "Could not read file as UTF-8 text."
                }
            case .failure(let error):
                importMessage = "Import error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Native Telegram MTProto Login Wizard Card
    private var telegramMTProtoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Telegram MTProto Login", systemImage: "paperplane.fill")
                    .font(.headline)
                    .foregroundColor(AppTheme.cyan)
                Spacer()
                statusBadge(
                    mtproto.isAuthorized ? "Connected" : (mtproto.authStage == .disconnected ? "Offline" : "Signing In"),
                    color: mtproto.isAuthorized ? AppTheme.emerald : AppTheme.amber
                )
            }

            Text("Sign in with your personal Telegram account (Phone + OTP) via official TDLib MTProto. Unlocks 2 GB downloads, restricted channel bypass, and direct channel uploads.")
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary)

            switch mtproto.authStage {
            case .ready:
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.emerald.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title3)
                            .foregroundColor(AppTheme.emerald)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mtproto.connectedUserName.isEmpty ? "Telegram Connected" : mtproto.connectedUserName)
                            .font(.subheadline.bold())
                            .foregroundColor(AppTheme.textPrimary)
                        Text("\(mtproto.connectedPhone) • \(mtproto.chats.count) chats loaded")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(AppTheme.emerald.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 10) {
                    Button {
                        mtproto.loadUserChats()
                    } label: {
                        Label("Refresh Chats", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.primary.opacity(0.2))
                            .foregroundColor(AppTheme.primaryLight)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        mtproto.logout()
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.danger.opacity(0.18))
                            .foregroundColor(AppTheme.danger)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

            case .disconnected, .connecting, .waitPhoneNumber:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mobile Number (with Country Code)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.emerald)

                    styledTextField("+959xxxxxxxxx (e.g. +1..., +95...)", text: $api.telegramPhone, keyboard: .phonePad)

                    HStack {
                        Text("Telegram API ID & API Hash")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Link("Get at my.telegram.org →", destination: URL(string: "https://my.telegram.org/apps")!)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppTheme.cyan)
                    }
                    .padding(.top, 4)

                    styledTextField("Telegram API ID (e.g. 12345678)", text: $api.telegramApiId, keyboard: .numberPad)
                    styledTextField("Telegram API Hash (32-char hex)", text: $api.telegramApiHash, keyboard: .asciiCapable)
                }

                Button {
                    mtproto.connectAndSendPhone(
                        phone: api.telegramPhone,
                        apiIdString: api.telegramApiId,
                        apiHash: api.telegramApiHash
                    )
                } label: {
                    if mtproto.isBusyAuth {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("Connecting & Sending OTP...")
                        }
                    } else {
                        Label("Send OTP Verification Code", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(color: AppTheme.emerald))
                .disabled(mtproto.isBusyAuth)

            case .waitCode:
                Text("Enter 5-Digit OTP Code from Telegram")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.amber)

                Text("Verification code sent to \(api.telegramPhone). Check your Telegram app messages.")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary)

                styledTextField("12345", text: $otpCodeInput, keyboard: .numberPad)

                Button {
                    mtproto.submitAuthCode(otpCodeInput)
                } label: {
                    if mtproto.isBusyAuth {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("Verifying OTP...")
                        }
                    } else {
                        Label("Verify OTP & Sign In", systemImage: "checkmark.circle.fill")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(color: AppTheme.emerald))
                .disabled(mtproto.isBusyAuth)

                Button {
                    otpCodeInput = ""
                    mtproto.resetAuthFlow()
                } label: {
                    Text("Change Phone Number or API Keys")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }

            case .waitPassword(let hint):
                Text("Two-Step Verification Password\(hint.isEmpty ? "" : " (Hint: \(hint))")")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.amber)

                SecureField("Enter Telegram 2FA Cloud Password", text: $twoFactorPasswordInput)
                    .padding(12)
                    .background(AppTheme.surfaceCardElevated)
                    .foregroundColor(AppTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.surfaceCardBorder, lineWidth: 1))

                Button {
                    mtproto.submitTwoFactorPassword(twoFactorPasswordInput)
                } label: {
                    if mtproto.isBusyAuth {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("Unlocking Account...")
                        }
                    } else {
                        Label("Unlock & Sign In", systemImage: "lock.open.fill")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(color: AppTheme.emerald))
                .disabled(mtproto.isBusyAuth)

                Button {
                    twoFactorPasswordInput = ""
                    mtproto.resetAuthFlow()
                } label: {
                    Text("Back to Login Form")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }

            if let msg = mtproto.authMessage, mtproto.authError == nil {
                statusFeedback(ok: true, message: msg)
            }
            if let err = mtproto.authError {
                statusFeedback(ok: false, message: err)
            }
        }
        .pipelineCard()
    }

    private func secretField(placeholder: String, text: Binding<String>, isRevealed: Binding<Bool>) -> some View {
        HStack {
            Group {
                if isRevealed.wrappedValue {
                    TextField(placeholder, text: text)
                } else {
                    SecureField(placeholder, text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundColor(AppTheme.textPrimary)

            Button {
                isRevealed.wrappedValue.toggle()
            } label: {
                Image(systemName: isRevealed.wrappedValue ? "eye.slash" : "eye")
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding(12)
        .background(AppTheme.surfaceCardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.surfaceCardBorder, lineWidth: 1))
    }

    private func styledTextField(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(AppTheme.surfaceCardElevated)
            .foregroundColor(AppTheme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.surfaceCardBorder, lineWidth: 1))
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func statusFeedback(ok: Bool, message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(message)
                .font(.caption)
        }
        .foregroundColor(ok ? AppTheme.emerald : AppTheme.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background((ok ? AppTheme.emerald : AppTheme.danger).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
