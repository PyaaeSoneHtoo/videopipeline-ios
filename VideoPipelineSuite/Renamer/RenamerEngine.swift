import Foundation

struct RenameItem: Identifiable, Hashable {
    let id = UUID()
    let fileURL: URL
    let originalName: String
    var newName: String
    var status: String = "Ready"
}

enum RenamerEngine {
    private static let commonResolutions: Set<String> = ["360", "480", "720", "1080", "1440", "2160"]

    private static let episodeKeywordPattern = "(?:^|[\\s._\\-])(?:ep|episode|e|part|pt|season|s|ch|chapter|vol|v)$"
    private static let trailingExplicitTagPattern = "(?:[\\s_-]*[\\(\\[](?:msg|msgid|id)[_\\s-]?\\d{1,12}[\\)\\]]|[\\s_-]+(?:msg|msgid|id)[_\\s-]?\\d{1,12})$"
    private static let leadingExplicitTagPattern = "^(?:[\\(\\[](?:msg|msgid|id)[_\\s-]?\\d{1,12}[\\)\\]][\\s_-]*|(?:msg|msgid)[_\\s-]?\\d{1,12}[\\s_-]+)"

    private static func stripExplicitTags(_ stem: String) -> String {
        var cleaned = stem
        while true {
            var updated = replaceRegex(pattern: trailingExplicitTagPattern, in: cleaned, with: "")
            updated = replaceRegex(pattern: leadingExplicitTagPattern, in: updated, with: "")
            if updated == cleaned { break }
            cleaned = updated
        }
        return cleaned
    }

    static func extractEpisodeNumber(_ stem: String) -> Int? {
        // 1. Explicit ep/episode/e/part prefix
        if let m1 = firstCapture(pattern: "(?:ep|episode|e|part|pt)[\\s\\-_.:]*0*(\\d{1,4})\\b", in: stem),
           let num = Int(m1) {
            return num
        }

        // 2. Standalone digits (last cluster)
        let matches = allCaptures(pattern: "\\b0*(\\d{1,4})\\b", in: stem).compactMap { Int($0) }
        if let last = matches.last {
            return last
        }

        // 3. Any digits
        if let m3 = firstCapture(pattern: "(\\d+)", in: stem),
           let num = Int(m3) {
            return num
        }

        return nil
    }

    static func stripTelegramMessageId(_ filename: String) -> (stem: String, ext: String) {
        let stem: String
        let ext: String
        if let dotIdx = filename.lastIndex(of: ".") {
            stem = String(filename[..<dotIdx])
            ext = String(filename[dotIdx...])
        } else {
            stem = filename
            ext = ""
        }

        var cleaned = stripExplicitTags(stem)
        let trimSet = CharacterSet(charactersIn: " _-.")

        if let range = firstMatchRange(pattern: "[\\s_]*_+\\d{1,12}$", in: cleaned) {
            let prefix = String(cleaned[..<range.lowerBound])
            let cleanPrefix = prefix.trimmingCharacters(in: trimSet)
            if !cleanPrefix.isEmpty && firstMatchRange(pattern: episodeKeywordPattern, in: prefix) == nil {
                if extractEpisodeNumber(cleanPrefix) != nil || cleanPrefix.lowercased() == "video" {
                    cleaned = prefix
                }
            }
        } else if let range = firstMatchRange(pattern: "[\\s_]*\\[(\\d{1,12})\\]$", in: cleaned),
                  let bracketNum = firstCapture(pattern: "[\\s_]*\\[(\\d{1,12})\\]$", in: cleaned) {
            if !commonResolutions.contains(bracketNum) {
                let prefix = String(cleaned[..<range.lowerBound])
                let cleanPrefix = prefix.trimmingCharacters(in: trimSet)
                if !cleanPrefix.isEmpty && (extractEpisodeNumber(cleanPrefix) != nil || cleanPrefix.lowercased() == "video") {
                    cleaned = prefix
                }
            }
        }

        cleaned = stripExplicitTags(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return (stem.trimmingCharacters(in: .whitespacesAndNewlines), ext)
        }
        return (cleaned, ext)
    }

    static func removeMessageIdOnly(_ originalName: String) -> String {
        let (cleanedStem, ext) = stripTelegramMessageId(originalName)
        return cleanedStem.isEmpty ? originalName : "\(cleanedStem)\(ext)"
    }

    static func cleanSeriesTitleHeuristic(_ stems: [String]) -> String {
        guard let first = stems.first else { return "Series" }
        let trimSet = CharacterSet(charactersIn: " _-.")

        var common = first
        for s in stems {
            while !s.hasPrefix(common) && !common.isEmpty {
                common.removeLast()
            }
        }
        common = common.trimmingCharacters(in: trimSet)
        let cleaned = replaceRegex(
            pattern: "[\\s\\-_.:]*(?:ep|episode|e|part)?[\\s\\-_.:]*\\d*$",
            in: common,
            with: ""
        ).trimmingCharacters(in: trimSet)
        if cleaned.count >= 2 { return cleaned }

        let cleanedFirst = replaceRegex(
            pattern: "[\\s\\-_.:]*(?:ep|episode|e|part)?[\\s\\-_.:]*\\d+.*$",
            in: first,
            with: ""
        ).trimmingCharacters(in: trimSet)
        if cleanedFirst.count >= 2 { return cleanedFirst }

        let fallback = String(first.prefix(30)).trimmingCharacters(in: trimSet)
        return fallback.isEmpty ? "Series" : fallback
    }

    static func formatSingleFilenameRegex(
        originalName: String,
        seriesTitle: String,
        totalCount: Int,
        fallbackIndex: Int = 1
    ) -> String {
        let (cleanedStem, ext) = stripTelegramMessageId(originalName)
        let epNum = extractEpisodeNumber(cleanedStem) ?? fallbackIndex
        let padding = totalCount >= 100 ? 3 : 2
        let paddedEp = String(format: "%0\(padding)d", epNum)
        let cleanSeries = seriesTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSeries = cleanSeries.isEmpty ? "Series" : cleanSeries
        return "\(finalSeries) Ep - \(paddedEp)\(ext)"
    }

    // MARK: - Regex Helpers
    private static func replaceRegex(pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: nsRange, withTemplate: template)
    }

    private static func firstMatchRange(pattern: String, in text: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange) else { return nil }
        return Range(match.range, in: text)
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func allCaptures(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}
