import SwiftUI
import UniformTypeIdentifiers

struct ApiSetupView: View {
    @ObservedObject private var api = ApiSettingsStore.shared

    @State private var showEnvImporter: Bool = false
    @State private var importMessage: String? = nil

    @State private var geminiStatus: (ok: Bool, msg: String)? = nil
    @State private var isTestingGemini: Bool = false

    @State private var deepseekStatus: (ok: Bool, msg: String)? = nil
    @State private var isTestingDeepSeek: Bool = false

    @State private var telegramStatus: (ok: Bool, msg: String)? = nil
    @State private var isTestingTelegram: Bool = false

    @State private var showGeminiKey: Bool = false
    @State private var showDeepSeekKey: Bool = false
    @State private var showBotToken: Bool = false

    var body: some View {
        ZStack {
            AppTheme.bgDark.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Quick .env / JSON Import Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Import API Config (.env / JSON)", systemImage: "square.and.arrow.down.on.square")
                                .font(.headline)
                                .foregroundColor(AppTheme.emerald)
                            Spacer()
                        }
                        Text("Import your `.env` or `credentials.json` directly from PC Video Pipeline Suite to auto-fill Gemini, DeepSeek, and Telegram credentials in 1 tap.")
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

                    // Preferred AI Engine Selector
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

                    // 1. Google Gemini API Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Google Gemini API", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundColor(AppTheme.primaryLight)
                            Spacer()
                            if api.hasGeminiKey {
                                statusBadge("Configured", color: AppTheme.emerald)
                            } else {
                                statusBadge("Not Set", color: AppTheme.textMuted)
                            }
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

                    // 2. DeepSeek API Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("DeepSeek AI API", systemImage: "brain.head.profile")
                                .font(.headline)
                                .foregroundColor(AppTheme.cyan)
                            Spacer()
                            if api.hasDeepSeekKey {
                                statusBadge("Configured", color: AppTheme.emerald)
                            } else {
                                statusBadge("Not Set", color: AppTheme.textMuted)
                            }
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

                    // 3. Telegram Account & Bot Login Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Telegram Login & API", systemImage: "paperplane.fill")
                                .font(.headline)
                                .foregroundColor(AppTheme.amber)
                            Spacer()
                            if api.isTelegramConfigured {
                                statusBadge(api.telegramConnectedUsername.isEmpty ? "Saved" : "@\(api.telegramConnectedUsername)", color: AppTheme.emerald)
                            } else {
                                statusBadge("Not Connected", color: AppTheme.textMuted)
                            }
                        }

                        Text("Connect your Telegram Bot Token (for instant native iOS video inbox & download) and/or store your MTProto API ID, API Hash & Phone Number.")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Telegram Bot Token (Recommended for iOS)")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(AppTheme.textSecondary)
                            secretField(
                                placeholder: "123456789:AAH...",
                                text: $api.telegramBotToken,
                                isRevealed: $showBotToken
                            )
                        }

                        Button {
                            isTestingTelegram = true
                            telegramStatus = nil
                            Task {
                                let res = await api.verifyTelegramBotToken()
                                telegramStatus = (res.ok, res.message)
                                isTestingTelegram = false
                            }
                        } label: {
                            if isTestingTelegram {
                                ProgressView().tint(.white)
                            } else {
                                Label("Login & Verify Telegram Bot", systemImage: "checkmark.seal.fill")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(AppTheme.amber)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .disabled(isTestingTelegram)

                        if let status = telegramStatus {
                            statusFeedback(ok: status.ok, message: status.msg)
                        }

                        Divider().background(AppTheme.surfaceCardBorder).padding(.vertical, 4)

                        // MTProto Account Credentials
                        HStack {
                            Text("Telegram MTProto Account (my.telegram.org)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Link("Get API ID", destination: URL(string: "https://my.telegram.org/apps")!)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(AppTheme.primaryLight)
                        }

                        styledTextField("Phone Number (+959...)", text: $api.telegramPhone, keyboard: .phonePad)
                        styledTextField("Telegram API ID (e.g. 12345678)", text: $api.telegramApiId, keyboard: .numberPad)
                        styledTextField("Telegram API Hash (32-char hex)", text: $api.telegramApiHash, keyboard: .asciiCapable)

                        if api.isTelegramConfigured {
                            Button(role: .destructive) {
                                api.clearTelegramLogin()
                                telegramStatus = (false, "Telegram credentials cleared.")
                            } label: {
                                Label("Disconnect Telegram", systemImage: "xmark.circle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(AppTheme.danger)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .pipelineCard()
                }
                .padding(16)
            }
        }
        .navigationTitle("API & Telegram Setup")
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
