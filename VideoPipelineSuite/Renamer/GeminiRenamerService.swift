import Foundation

enum GeminiRenamerService {
    static func renameWithAI(
        items: [RenameItem],
        provider: AIProvider,
        apiKey: String,
        modelName: String,
        deepseekEndpoint: String = "https://api.deepseek.com/chat/completions"
    ) async -> (items: [RenameItem], usedAI: Bool, note: String) {
        guard !items.isEmpty else { return (items, false, "No files to rename.") }

        let stems = items.map { RenamerEngine.stripTelegramMessageId($0.originalName).stem }
        let heuristicSeries = RenamerEngine.cleanSeriesTitleHeuristic(stems)

        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            let fallback = applyRegexFallback(items: items, series: heuristicSeries)
            return (fallback, false, "No \(provider.rawValue) API Key set — used Fast Regex fallback. Add your key in API Setup.")
        }

        let fileListText = items.map { $0.originalName }.joined(separator: "\n")
        let prompt = """
        You are a professional video series organizer.
        Analyze the following list of filenames from a drama/anime series:
        \(fileListText)

        Rules:
        1. Detect the unified series title (Keep Burmese/Chinese/English names accurately).
        2. Extract the true episode number for each file.
        3. Remove all Telegram message ID noise, hashes, and channel tags.
        4. Output strictly valid JSON with this exact schema:
        {
          "series_name": "\(heuristicSeries)",
          "items": [
            { "original": "original_filename.mp4", "new_name": "\(heuristicSeries) Ep - 01.mp4" }
          ]
        }
        """

        do {
            let rawText: String
            switch provider {
            case .gemini:
                rawText = try await callGemini(prompt: prompt, apiKey: cleanKey, model: modelName)
            case .deepseek:
                rawText = try await callDeepSeek(prompt: prompt, apiKey: cleanKey, model: modelName, endpoint: deepseekEndpoint)
            }

            let cleanedJSON = extractJSONBlock(from: rawText)
            if let jsonData = cleanedJSON.data(using: .utf8),
               let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let mappedItems = parsed["items"] as? [[String: Any]] {
                var nameMap: [String: String] = [:]
                for entry in mappedItems {
                    if let orig = entry["original"] as? String,
                       let newName = entry["new_name"] as? String,
                       !orig.isEmpty, !newName.isEmpty {
                        nameMap[orig] = newName
                    }
                }

                let updated = items.enumerated().map { idx, item -> RenameItem in
                    var copy = item
                    if let aiName = nameMap[item.originalName] {
                        copy.newName = aiName
                    } else {
                        copy.newName = RenamerEngine.formatSingleFilenameRegex(
                            originalName: item.originalName,
                            seriesTitle: heuristicSeries,
                            totalCount: items.count,
                            fallbackIndex: idx + 1
                        )
                    }
                    copy.status = "\(provider.rawValue) Ready"
                    return copy
                }
                return (updated, true, "\(provider.rawValue) AI renaming generated successfully!")
            }
        } catch {
            let fallback = applyRegexFallback(items: items, series: heuristicSeries)
            return (fallback, false, "\(provider.rawValue) error (\(error.localizedDescription)) — used Fast Regex fallback.")
        }

        let fallback = applyRegexFallback(items: items, series: heuristicSeries)
        return (fallback, false, "Could not parse \(provider.rawValue) JSON — used Fast Regex fallback.")
    }

    private static func callGemini(prompt: String, apiKey: String, model: String) async throws -> String {
        let cascadeList = ApiSettingsStore.preferredGeminiOrder
        var modelsToTry: [String] = []
        if !model.isEmpty && model != "auto" && !model.contains("2.5") && !model.contains("2.0") && !model.contains("1.5") {
            modelsToTry.append(model)
        }
        for m in cascadeList {
            if !modelsToTry.contains(m) {
                modelsToTry.append(m)
            }
        }

        let payload: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)

        var lastError: Error?
        for currModel in modelsToTry {
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(currModel):generateContent?key=\(apiKey)") else {
                continue
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 30
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = bodyData

            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(code) {
                    if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let candidates = root["candidates"] as? [[String: Any]],
                       let content = candidates.first?["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]],
                       let text = parts.first?["text"] as? String {
                        return text
                    }
                    return ""
                }

                if code == 400 || code == 401 || code == 403 {
                    let errObj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
                    let msg = errObj?["message"] as? String ?? "HTTP \(code)"
                    if msg.contains("API_KEY_INVALID") || code == 401 {
                        throw NSError(domain: "AIRenamer", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
                    }
                }

                let errObj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
                let msg = errObj?["message"] as? String ?? "\(currModel) HTTP \(code)"
                lastError = NSError(domain: "AIRenamer", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
            } catch {
                if let nsErr = error as NSError?, nsErr.domain == "AIRenamer" && nsErr.code == 401 {
                    throw error
                }
                lastError = error
            }
        }

        throw lastError ?? NSError(domain: "AIRenamer", code: -1, userInfo: [NSLocalizedDescriptionKey: "All Gemini models failed."])
    }

    private static func callDeepSeek(prompt: String, apiKey: String, model: String, endpoint: String) async throws -> String {
        guard let url = URL(string: endpoint.isEmpty ? "https://api.deepseek.com/chat/completions" : endpoint) else {
            throw NSError(domain: "AIRenamer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid DeepSeek endpoint"])
        }
        let payload: [String: Any] = [
            "model": model.isEmpty ? "deepseek-chat" : model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.1
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw NSError(domain: "AIRenamer", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
        }
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = root["choices"] as? [[String: Any]],
           let msg = choices.first?["message"] as? [String: Any],
           let content = msg["content"] as? String {
            return content
        }
        return ""
    }

    private static func applyRegexFallback(items: [RenameItem], series: String) -> [RenameItem] {
        items.enumerated().map { idx, item in
            var copy = item
            copy.newName = RenamerEngine.formatSingleFilenameRegex(
                originalName: item.originalName,
                seriesTitle: series,
                totalCount: items.count,
                fallbackIndex: idx + 1
            )
            copy.status = "Regex Ready"
            return copy
        }
    }

    private static func extractJSONBlock(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.range(of: "```json"),
           let end = trimmed.range(of: "```", range: start.upperBound..<trimmed.endIndex) {
            return String(trimmed[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}") {
            return String(trimmed[firstBrace...lastBrace])
        }
        return trimmed
    }
}
