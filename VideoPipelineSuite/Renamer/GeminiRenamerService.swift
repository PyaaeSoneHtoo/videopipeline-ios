import Foundation

enum GeminiRenamerService {
    private static let apiKey = "AIzaSyDDTgn3xb76GgMEkpW2fq9H_NFZBX_5imU"
    private static let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)")!

    static func renameWithGemini(items: [RenameItem]) async -> [RenameItem] {
        guard !items.isEmpty else { return items }

        let stems = items.map { RenamerEngine.stripTelegramMessageId($0.originalName).stem }
        let heuristicSeries = RenamerEngine.cleanSeriesTitleHeuristic(stems)

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

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ]
        ]

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = root["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let content = firstCandidate["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let rawText = parts.first?["text"] as? String {

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

                    return items.enumerated().map { idx, item in
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
                        copy.status = "AI Ready"
                        return copy
                    }
                }
            }
        } catch {
            // Fall through to fast regex fallback
        }

        return items.enumerated().map { idx, item in
            var copy = item
            copy.newName = RenamerEngine.formatSingleFilenameRegex(
                originalName: item.originalName,
                seriesTitle: heuristicSeries,
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
