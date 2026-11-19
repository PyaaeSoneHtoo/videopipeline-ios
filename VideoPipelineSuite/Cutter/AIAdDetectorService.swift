import Foundation
import AVFoundation
import UIKit

struct AdDetectionResult {
    let adDetected: Bool
    let cutSeconds: Double
    let adType: String
    let reason: String
}

enum AIAdDetectorService {
    static func detectIntroAd(
        videoURL: URL,
        provider: AIProvider,
        apiKey: String,
        modelName: String,
        deepseekEndpoint: String = "https://api.deepseek.com/chat/completions",
        scanSeconds: Int = 30
    ) async throws -> AdDetectionResult {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NSError(
                domain: "AIAdDetector",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Please set your \(provider.rawValue) API Key in API & Telegram Setup first."]
            )
        }

        // Extract 1 frame every 2 seconds across the intro window (lightweight & fast on iOS)
        let frames = try await extractBase64Frames(from: videoURL, maxSeconds: scanSeconds, stepSeconds: 2)
        guard !frames.isEmpty else {
            throw NSError(
                domain: "AIAdDetector",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Could not extract video frames for AI inspection."]
            )
        }

        let prompt = """
        You are an expert video editor AI specializing in removing sponsor bumper ads, casino commercials, and slot promos from the start of videos.
        I have provided \(frames.count) chronological frames sampled every 2 seconds from the beginning of the video.
        Determine if an intro advertisement is present and find the exact timestamp in seconds where the ad ends and the main content begins.
        Return strictly valid JSON with no markdown:
        {
          "ad_detected": true,
          "ad_type": "Casino / Sponsor / Intro",
          "cut_seconds": 10.0,
          "reason": "Sponsor banner ends at 10.0s."
        }
        If no ad is found, set ad_detected to false and cut_seconds to 0.0.
        """

        let rawResponse: String
        switch provider {
        case .gemini:
            rawResponse = try await queryGeminiVision(apiKey: cleanKey, model: modelName, prompt: prompt, frames: frames)
        case .deepseek:
            rawResponse = try await queryDeepSeekVision(apiKey: cleanKey, model: modelName, endpoint: deepseekEndpoint, prompt: prompt, frames: frames)
        }

        return parseDetectionJSON(rawResponse)
    }

    private static func extractBase64Frames(from url: URL, maxSeconds: Int, stepSeconds: Int) async throws -> [(ts: Double, b64: String)] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let totalSec = max(1.0, CMTimeGetSeconds(duration))
        let limit = min(Double(maxSeconds), totalSec)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var results: [(Double, String)] = []
        var sec: Double = 0
        while sec <= limit {
            let cmTime = CMTime(seconds: sec, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) {
                let uiImg = UIImage(cgImage: cgImage)
                if let jpegData = uiImg.jpegData(compressionQuality: 0.55) {
                    results.append((sec, jpegData.base64EncodedString()))
                }
            }
            sec += Double(stepSeconds)
        }
        return results
    }

    private static func queryGeminiVision(
        apiKey: String,
        model: String,
        prompt: String,
        frames: [(ts: Double, b64: String)]
    ) async throws -> String {
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

        var parts: [[String: Any]] = [["text": prompt]]
        for f in frames {
            parts.append(["text": "Frame at \(String(format: "%.1f", f.ts))s:"])
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": f.b64
                ]
            ])
        }

        let payload: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": ["temperature": 0.1]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)

        var lastError: Error?
        for currModel in modelsToTry {
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(currModel):generateContent?key=\(apiKey)") else {
                continue
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 45
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = bodyData

            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(code) {
                    if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let candidates = root["candidates"] as? [[String: Any]],
                       let content = candidates.first?["content"] as? [String: Any],
                       let respParts = content["parts"] as? [[String: Any]],
                       let text = respParts.first?["text"] as? String {
                        return text
                    }
                    return "{}"
                }

                if code == 400 || code == 401 || code == 403 {
                    let errObj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
                    let msg = errObj?["message"] as? String ?? "HTTP \(code)"
                    if msg.contains("API_KEY_INVALID") || code == 401 {
                        throw NSError(domain: "AIAdDetector", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
                    }
                }

                let errObj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
                let msg = errObj?["message"] as? String ?? "\(currModel) HTTP \(code)"
                lastError = NSError(domain: "AIAdDetector", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
            } catch {
                if let nsErr = error as NSError?, nsErr.domain == "AIAdDetector" && nsErr.code == 401 {
                    throw error
                }
                lastError = error
            }
        }

        throw lastError ?? NSError(domain: "AIAdDetector", code: -1, userInfo: [NSLocalizedDescriptionKey: "All Gemini models failed."])
    }

    private static func queryDeepSeekVision(
        apiKey: String,
        model: String,
        endpoint: String,
        prompt: String,
        frames: [(ts: Double, b64: String)]
    ) async throws -> String {
        guard let url = URL(string: endpoint.isEmpty ? "https://api.deepseek.com/chat/completions" : endpoint) else {
            throw NSError(domain: "AIAdDetector", code: -4, userInfo: [NSLocalizedDescriptionKey: "Invalid DeepSeek endpoint URL"])
        }

        var userContent: [[String: Any]] = [["type": "text", "text": prompt]]
        for f in frames {
            userContent.append(["type": "text", "text": "Frame at \(String(format: "%.1f", f.ts))s:"])
            userContent.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(f.b64)"]
            ])
        }

        let payload: [String: Any] = [
            "model": model.isEmpty ? "deepseek-flash" : model,
            "messages": [["role": "user", "content": userContent]],
            "temperature": 0.1,
            "max_tokens": 1024
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let errObj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
            let msg = errObj?["message"] as? String ?? "DeepSeek HTTP \(code)"
            throw NSError(domain: "AIAdDetector", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = root["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        return "{}"
    }

    private static func parseDetectionJSON(_ raw: String) -> AdDetectionResult {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = cleaned.firstIndex(of: "{"), let last = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[first...last])
        }

        if let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let detected = json["ad_detected"] as? Bool ?? false
            let cutSec: Double
            if let d = json["cut_seconds"] as? Double {
                cutSec = d
            } else if let i = json["cut_seconds"] as? Int {
                cutSec = Double(i)
            } else if let s = json["cut_seconds"] as? String, let parsed = Double(s) {
                cutSec = parsed
            } else {
                cutSec = 0.0
            }
            let adType = json["ad_type"] as? String ?? "Intro Ad"
            let reason = json["reason"] as? String ?? (detected ? "Ad detected up to \(cutSec)s." : "No intro ad detected.")
            return AdDetectionResult(adDetected: detected, cutSeconds: max(0.0, cutSec), adType: adType, reason: reason)
        }

        return AdDetectionResult(adDetected: false, cutSeconds: 0.0, adType: "Unknown", reason: "Could not parse AI response.")
    }
}
