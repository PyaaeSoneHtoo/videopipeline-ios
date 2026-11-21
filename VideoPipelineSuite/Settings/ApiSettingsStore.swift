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
    }

    @Published var geminiApiKey: String {
        didSet { UserDefaults.standard.set(geminiApiKey, forKey: Keys.geminiApiKey) }
    }
    @Published var geminiModel: String {
        didSet { UserDefaults.standard.set(geminiModel, forKey: Keys.geminiModel) }
    }
    @Published var geminiModels: [(id: String, label: String)] = ApiSettingsStore.defaultGeminiModels
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

    // Telegram MTProto Credentials (my.telegram.org)
    @Published var telegramPhone: String {
        didSet { UserDefaults.standard.set(telegramPhone, forKey: Keys.tgPhone) }
    }
    @Published var telegramApiId: String {
        didSet { UserDefaults.standard.set(telegramApiId, forKey: Keys.tgApiId) }
    }
    @Published var telegramApiHash: String {
        didSet { UserDefaults.standard.set(telegramApiHash, forKey: Keys.tgApiHash) }
    }

    var hasGeminiKey: Bool { !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasDeepSeekKey: Bool { !deepseekApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasTelegramMTProtoKeys: Bool {
        Int(telegramApiId.trimmingCharacters(in: .whitespacesAndNewlines)) != nil &&
        !telegramApiHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let defaultGeminiModels: [(id: String, label: String)] = [
        ("auto", "🔄 Auto-Cascade (Smart Best Available)"),
        ("gemini-3-flash-preview", "⚡ Gemini 3 Flash Preview (Recommended)"),
        ("gemini-3.5-flash-lite", "🚀 Gemini 3.5 Flash-Lite (Ultra Fast)"),
        ("gemini-3.1-flash-lite", "🟢 Gemini 3.1 Flash-Lite (High Quota)"),
        ("gemini-flash-lite-latest", "🔹 Gemini Flash-Lite Latest"),
        ("gemini-3.1-flash-lite-preview", "🧪 Gemini 3.1 Flash-Lite Preview"),
        ("gemini-robotics-er-2-preview", "🤖 Gemini Robotics-ER 2 Preview"),
        ("gemini-3.8-flash", "🌟 Gemini 3.8 Flash"),
        ("gemini-3.7-flash", "✨ Gemini 3.7 Flash"),
        ("gemini-3.1-pro-preview", "🧠 Gemini 3.1 Pro Preview"),
        ("gemini-pro-latest", "💎 Gemini Pro Latest")
    ]

    static let preferredGeminiOrder: [String] = [
        "gemini-3-flash-preview",
        "gemini-3.5-flash-lite",
        "gemini-3.1-flash-lite",
        "gemini-flash-lite-latest",
        "gemini-3.1-flash-lite-preview",
        "gemini-robotics-er-2-preview",
        "gemini-3.8-flash",
        "gemini-3.7-flash",
        "gemini-3.1-pro-preview",
        "gemini-pro-latest"
    ]

    static let deepseekModels: [(id: String, label: String)] = [
        ("deepseek-chat", "DeepSeek Chat (V3 - Recommended)"),
        ("deepseek-flash", "DeepSeek Flash (Multimodal Vision)"),
        ("deepseek-reasoner", "DeepSeek Reasoner (R1)")
    ]

    private init() {
        let d = UserDefaults.standard
        self.geminiApiKey = d.string(forKey: Keys.geminiApiKey) ?? ""
        var savedModel = d.string(forKey: Keys.geminiModel) ?? "auto"
        if savedModel.contains("2.5") || savedModel.contains("2.0") || savedModel.contains("1.5") {
            savedModel = "auto"
        }
        self.geminiModel = savedModel
        self.deepseekApiKey = d.string(forKey: Keys.deepseekApiKey) ?? ""
        self.deepseekModel = d.string(forKey: Keys.deepseekModel) ?? "deepseek-chat"
        self.deepseekEndpoint = d.string(forKey: Keys.deepseekEndpoint) ?? "https://api.deepseek.com/chat/completions"
        let rawProv = d.string(forKey: Keys.preferredAIProvider) ?? AIProvider.gemini.rawValue
        self.preferredProvider = AIProvider(rawValue: rawProv) ?? .gemini

        self.telegramPhone = d.string(forKey: Keys.tgPhone) ?? ""
        let savedApiId = d.string(forKey: Keys.tgApiId) ?? ""
        self.telegramApiId = savedApiId.isEmpty ? "33821639" : savedApiId
        let savedApiHash = d.string(forKey: Keys.tgApiHash) ?? ""
        self.telegramApiHash = savedApiHash.isEmpty ? "22533aeb1ea63aab9329e0f47f280118" : savedApiHash
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
            if let v = stringValue(json, keys: ["TELEGRAM_API_ID", "API_ID", "api_id"]) {
                telegramApiId = v; imported.append("MTProto API ID")
            }
            if let v = stringValue(json, keys: ["TELEGRAM_API_HASH", "API_HASH", "api_hash"]) {
                telegramApiHash = v; imported.append("MTProto API Hash")
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
            case "TELEGRAM_API_ID", "API_ID":
                telegramApiId = val; imported.append("MTProto API ID")
            case "TELEGRAM_API_HASH", "API_HASH":
                telegramApiHash = val; imported.append("MTProto API Hash")
            case "TELEGRAM_PHONE", "PHONE":
                telegramPhone = val; imported.append("Telegram Phone")
            default:
                break
            }
        }

        return (imported.count, imported.isEmpty ? "No recognized keys found. Supported: GEMINI_API_KEY, DEEPSEEK_API_KEY, TELEGRAM_API_ID, TELEGRAM_API_HASH, TELEGRAM_PHONE." : "Imported: \(imported.joined(separator: ", "))")
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

    // MARK: - Live AI API Verifiers
    func testGeminiKey() async -> (ok: Bool, message: String) {
        let key = geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return (false, "Enter a Gemini API Key first.") }

        // 1. Discover available models from the account
        var discoveredModelIds: [String] = []
        if let listUrl = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(key)") {
            var listReq = URLRequest(url: listUrl)
            listReq.timeoutInterval = 15
            if let (data, response) = try? await URLSession.shared.data(for: listReq),
               let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let modelsArr = root["models"] as? [[String: Any]] {

                var parsedList: [(id: String, label: String)] = [
                    ("auto", "🔄 Auto-Cascade (Smart Best Available)")
                ]

                let deprecatedModels = ["gemini-2.5-flash", "gemini-2.0-flash", "gemini-1.5-flash", "gemini-1.5-pro", "gemini-2.0-flash-lite", "gemini-2.0-pro-exp"]

                for m in modelsArr {
                    guard let rawName = m["name"] as? String else { continue }
                    let cleanId = rawName.replacingOccurrences(of: "models/", with: "")
                    let methods = m["supportedGenerationMethods"] as? [String] ?? []
                    guard methods.contains("generateContent") else { continue }
                    if deprecatedModels.contains(cleanId) { continue }

                    discoveredModelIds.append(cleanId)
                    let dName = m["displayName"] as? String ?? cleanId
                    parsedList.append((cleanId, "\(dName) (\(cleanId))"))
                }

                if parsedList.count > 1 {
                    self.geminiModels = parsedList
                }
            }
        }

        // 2. Cascade test candidates
        var candidatesToTest: [String] = []
        if !geminiModel.isEmpty && geminiModel != "auto" && !geminiModel.contains("2.5") && !geminiModel.contains("2.0") && !geminiModel.contains("1.5") {
            candidatesToTest.append(geminiModel)
        }
        for pref in ApiSettingsStore.preferredGeminiOrder {
            if !candidatesToTest.contains(pref) {
                candidatesToTest.append(pref)
            }
        }
        for disc in discoveredModelIds {
            if !disc.contains("2.5") && !disc.contains("2.0") && !disc.contains("1.5") && !candidatesToTest.contains(disc) {
                candidatesToTest.append(disc)
            }
        }
        if candidatesToTest.isEmpty {
            candidatesToTest = ApiSettingsStore.preferredGeminiOrder
        }

        // Test each candidate until one passes
        var lastErrorMsg = ""
        var idx = 0
        while idx < candidatesToTest.count {
            let candidate = candidatesToTest[idx]
            idx += 1
            guard let genUrl = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(candidate):generateContent?key=\(key)") else { continue }
            var testReq = URLRequest(url: genUrl)
            testReq.httpMethod = "POST"
            testReq.timeoutInterval = 15
            testReq.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "contents": [["parts": [["text": "Ping test"]]]]
            ]
            testReq.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            do {
                let (data, response) = try await URLSession.shared.data(for: testReq)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(code) {
                    self.geminiModel = candidate
                    return (true, "Gemini key verified! Active model: \(candidate)")
                }

                let errObj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
                let msg = errObj?["message"] as? String ?? "HTTP \(code)"

                if code == 400 || code == 401 || code == 403 {
                    if msg.contains("API_KEY_INVALID") || msg.contains("API key not valid") || code == 401 {
                        return (false, "Invalid Gemini API Key: \(msg)")
                    }
                }

                // If Google suggests a replacement model in the error message
                if let range = msg.range(of: "models/(gemini-[\\w\\.\\-]+)", options: .regularExpression) {
                    let suggested = String(msg[range]).replacingOccurrences(of: "models/", with: "")
                    if !candidatesToTest.contains(suggested) {
                        candidatesToTest.append(suggested)
                    }
                }

                lastErrorMsg = "\(candidate) (HTTP \(code))"
            } catch {
                lastErrorMsg = error.localizedDescription
            }
        }

        return (false, "Could not find an active Gemini model. Last tried: \(lastErrorMsg)")
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
}
