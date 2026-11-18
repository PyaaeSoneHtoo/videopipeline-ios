import Foundation
import Combine

enum AIProvider: String, CaseIterable, Identifiable {
    case gemini = "Gemini"
    case deepseek = "DeepSeek"

    var id: String { rawValue }
}

@MainActor
final class ApiSettingsStore: ObservableObject {
    static let shared = ApiSettingsStore()

    private enum Keys {
        static let geminiApiKey = "vp_gemini_api_key"
        static let geminiModel = "vp_gemini_model"
        static let deepseekApiKey = "vp_deepseek_api_key"
        static let deepseekModel = "vp_deepseek_model"
        static let deepseekEndpoint = "vp_deepseek_endpoint"
        static let preferredAIProvider = "vp_preferred_ai_provider"

        static let tgPhone = "vp_tg_phone"
        static let tgApiId = "vp_tg_api_id"
        static let tgApiHash = "vp_tg_api_hash"
        static let tgBotToken = "vp_tg_bot_token"
        static let tgConnectedName = "vp_tg_connected_name"
        static let tgConnectedUsername = "vp_tg_connected_username"
    }

    @Published var geminiApiKey: String {
        didSet { UserDefaults.standard.set(geminiApiKey, forKey: Keys.geminiApiKey) }
    }
    @Published var geminiModel: String {
        didSet { UserDefaults.standard.set(geminiModel, forKey: Keys.geminiModel) }
    }
    @Published var deepseekApiKey: String {
        didSet { UserDefaults.standard.set(deepseekApiKey, forKey: Keys.deepseekApiKey) }
    }
    @Published var deepseekModel: String {
        didSet { UserDefaults.standard.set(deepseekModel, forKey: Keys.deepseekModel) }
    }
    @Published var deepseekEndpoint: String {
        didSet { UserDefaults.standard.set(deepseekEndpoint, forKey: Keys.deepseekEndpoint) }
    }
    @Published var preferredProvider: AIProvider {
        didSet { UserDefaults.standard.set(preferredProvider.rawValue, forKey: Keys.preferredAIProvider) }
    }

    // Telegram Credentials
    @Published var telegramPhone: String {
        didSet { UserDefaults.standard.set(telegramPhone, forKey: Keys.tgPhone) }
    }
    @Published var telegramApiId: String {
        didSet { UserDefaults.standard.set(telegramApiId, forKey: Keys.tgApiId) }
    }
    @Published var telegramApiHash: String {
        didSet { UserDefaults.standard.set(telegramApiHash, forKey: Keys.tgApiHash) }
    }
    @Published var telegramBotToken: String {
        didSet { UserDefaults.standard.set(telegramBotToken, forKey: Keys.tgBotToken) }
    }
    @Published var telegramConnectedName: String {
        didSet { UserDefaults.standard.set(telegramConnectedName, forKey: Keys.tgConnectedName) }
    }
    @Published var telegramConnectedUsername: String {
        didSet { UserDefaults.standard.set(telegramConnectedUsername, forKey: Keys.tgConnectedUsername) }
    }

    var hasGeminiKey: Bool { !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasDeepSeekKey: Bool { !deepseekApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasTelegramBot: Bool { !telegramBotToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasTelegramMTProto: Bool {
        !telegramPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !telegramApiId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !telegramApiHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var isTelegramConfigured: Bool { hasTelegramBot || hasTelegramMTProto }

    static let geminiModels: [(id: String, label: String)] = [
        ("gemini-2.5-flash", "Gemini 2.5 Flash (Recommended)"),
        ("gemini-2.0-flash", "Gemini 2.0 Flash (Fast)"),
        ("gemini-1.5-flash", "Gemini 1.5 Flash (Stable)"),
        ("gemini-2.5-pro", "Gemini 2.5 Pro (High Accuracy)")
    ]

    static let deepseekModels: [(id: String, label: String)] = [
        ("deepseek-chat", "DeepSeek Chat (V3 - Recommended)"),
        ("deepseek-flash", "DeepSeek Flash (Multimodal Vision)"),
        ("deepseek-reasoner", "DeepSeek Reasoner (R1)")
    ]

    private init() {
        let d = UserDefaults.standard
        self.geminiApiKey = d.string(forKey: Keys.geminiApiKey) ?? ""
        self.geminiModel = d.string(forKey: Keys.geminiModel) ?? "gemini-2.5-flash"
        self.deepseekApiKey = d.string(forKey: Keys.deepseekApiKey) ?? ""
        self.deepseekModel = d.string(forKey: Keys.deepseekModel) ?? "deepseek-chat"
        self.deepseekEndpoint = d.string(forKey: Keys.deepseekEndpoint) ?? "https://api.deepseek.com/chat/completions"
        let rawProv = d.string(forKey: Keys.preferredAIProvider) ?? AIProvider.gemini.rawValue
        self.preferredProvider = AIProvider(rawValue: rawProv) ?? .gemini

        self.telegramPhone = d.string(forKey: Keys.tgPhone) ?? ""
        self.telegramApiId = d.string(forKey: Keys.tgApiId) ?? ""
        self.telegramApiHash = d.string(forKey: Keys.tgApiHash) ?? ""
        self.telegramBotToken = d.string(forKey: Keys.tgBotToken) ?? ""
        self.telegramConnectedName = d.string(forKey: Keys.tgConnectedName) ?? ""
        self.telegramConnectedUsername = d.string(forKey: Keys.tgConnectedUsername) ?? ""
    }

    // MARK: - Import .env or JSON Config File (from PC Video Pipeline Suite)
    func importConfig(from text: String) -> (importedCount: Int, summary: String) {
        var imported: [String] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Try JSON import first
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let v = stringValue(json, keys: ["GEMINI_API_KEY", "gemini_api_key", "geminiKey"]) {
                geminiApiKey = v; imported.append("Gemini Key")
            }
            if let v = stringValue(json, keys: ["DEEPSEEK_API_KEY", "deepseek_api_key", "deepseekKey"]) {
                deepseekApiKey = v; imported.append("DeepSeek Key")
            }
            if let v = stringValue(json, keys: ["TELEGRAM_BOT_TOKEN", "BOT_TOKEN", "bot_token"]) {
                telegramBotToken = v; imported.append("Telegram Bot Token")
            }
            if let v = stringValue(json, keys: ["TELEGRAM_API_ID", "API_ID", "api_id"]) {
                telegramApiId = v; imported.append("Telegram API ID")
            }
            if let v = stringValue(json, keys: ["TELEGRAM_API_HASH", "API_HASH", "api_hash"]) {
                telegramApiHash = v; imported.append("Telegram API Hash")
            }
            if let v = stringValue(json, keys: ["TELEGRAM_PHONE", "PHONE", "phone"]) {
                telegramPhone = v; imported.append("Telegram Phone")
            }
            return (imported.count, imported.isEmpty ? "No recognized API keys found in JSON." : "Imported: \(imported.joined(separator: ", "))")
        }

        // 2. Parse .env KEY=VALUE lines
        let lines = trimmed.components(separatedBy: .newlines)
        for line in lines {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty || clean.hasPrefix("#") { continue }
            guard let eqIdx = clean.firstIndex(of: "=") else { continue }
            let key = String(clean[..<eqIdx]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            var val = String(clean[clean.index(after: eqIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                val = String(val.dropFirst().dropLast())
            }
            guard !val.isEmpty else { continue }

            switch key {
            case "GEMINI_API_KEY":
                geminiApiKey = val; imported.append("Gemini Key")
            case "DEEPSEEK_API_KEY":
                deepseekApiKey = val; imported.append("DeepSeek Key")
            case "DEEPSEEK_MODEL":
                deepseekModel = val; imported.append("DeepSeek Model")
            case "DEEPSEEK_ENDPOINT":
                deepseekEndpoint = val
            case "TELEGRAM_BOT_TOKEN", "BOT_TOKEN":
                telegramBotToken = val; imported.append("Telegram Bot Token")
            case "TELEGRAM_API_ID", "API_ID":
                telegramApiId = val; imported.append("Telegram API ID")
            case "TELEGRAM_API_HASH", "API_HASH":
                telegramApiHash = val; imported.append("Telegram API Hash")
            case "TELEGRAM_PHONE", "PHONE":
                telegramPhone = val; imported.append("Telegram Phone")
            default:
                break
            }
        }

        return (imported.count, imported.isEmpty ? "No recognized keys found. Supported: GEMINI_API_KEY, DEEPSEEK_API_KEY, TELEGRAM_BOT_TOKEN, TELEGRAM_API_ID, TELEGRAM_API_HASH, TELEGRAM_PHONE." : "Imported: \(imported.joined(separator: ", "))")
    }

    private func stringValue(_ dict: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let s = dict[k] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let n = dict[k] as? NSNumber {
                return n.stringValue
            }
        }
        return nil
    }

    // MARK: - Live API Verifiers
    func testGeminiKey() async -> (ok: Bool, message: String) {
        let key = geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return (false, "Enter a Gemini API Key first.") }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(key)") else {
            return (false, "Invalid API key format.")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) {
                return (true, "Gemini API Key verified & active!")
            } else {
                let err = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
                let msg = err?["message"] as? String ?? "HTTP \(code)"
                return (false, "Gemini error: \(msg)")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func testDeepSeekKey() async -> (ok: Bool, message: String) {
        let key = deepseekApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return (false, "Enter a DeepSeek API Key first.") }
        guard let url = URL(string: "https://api.deepseek.com/models") else {
            return (false, "Invalid endpoint.")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) {
                return (true, "DeepSeek API Key verified & active!")
            } else {
                let err = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
                let msg = err?["message"] as? String ?? "HTTP \(code)"
                return (false, "DeepSeek error: \(msg)")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func verifyTelegramBotToken() async -> (ok: Bool, message: String) {
        let token = telegramBotToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return (false, "Enter your Telegram Bot Token first.") }
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/getMe") else {
            return (false, "Invalid Telegram Bot Token format.")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = json["ok"] as? Bool, ok,
               let result = json["result"] as? [String: Any] {
                let firstName = result["first_name"] as? String ?? "Telegram Bot"
                let username = result["username"] as? String ?? ""
                self.telegramConnectedName = firstName
                self.telegramConnectedUsername = username
                return (true, "Connected to Telegram as \(firstName) (@\(username))!")
            } else {
                let desc = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["description"] as? String ?? "Invalid Bot Token (HTTP \(code))"
                return (false, "Telegram error: \(desc)")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func clearTelegramLogin() {
        telegramPhone = ""
        telegramApiId = ""
        telegramApiHash = ""
        telegramBotToken = ""
        telegramConnectedName = ""
        telegramConnectedUsername = ""
    }
}
