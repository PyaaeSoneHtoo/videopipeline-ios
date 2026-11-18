import Foundation
import AVFoundation
import UIKit

struct VideoAssetMetadata {
    let url: URL
    let fileName: String
    let fileSizeBytes: Int64
    let durationSeconds: Double
    let resolutionText: String
    let thumbnail: UIImage?
}

struct DiscoveredTelegramChat: Identifiable, Hashable {
    let id: String
    let title: String
    let type: String
}

struct UploadQueueItem: Identifiable {
    let id = UUID()
    let fileName: String
    let targetChat: String
    let caption: String
    let scheduledAt: Date?
    var status: String
    var isCompleted: Bool
    var isFailed: Bool
}

final class TelegramUploadManager: NSObject, ObservableObject, URLSessionTaskDelegate {
    @Published var isUploading: Bool = false
    @Published var progress: Double = 0
    @Published var statusText: String = ""
    @Published var speedText: String = ""
    @Published var errorMessage: String? = nil
    @Published var successMessage: String? = nil
    @Published var queueHistory: [UploadQueueItem] = []

    private var startTime: Date = Date()
    private var activeTask: URLSessionUploadTask?
    private var activeSession: URLSession?
    private var tempMultipartURL: URL?

    func uploadVideo(
        botToken: String,
        chatId: String,
        videoURL: URL,
        caption: String,
        protectContent: Bool,
        disableNotification: Bool,
        supportsStreaming: Bool = true
    ) {
        let token = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = chatId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !token.isEmpty else {
            errorMessage = "Please connect your Telegram Bot Token in API & Telegram Setup first."
            return
        }
        guard !target.isEmpty else {
            errorMessage = "Please enter a target Channel (@username) or Chat ID (-100...)."
            return
        }
        guard let endpoint = URL(string: "https://api.telegram.org/bot\(token)/sendVideo") else {
            errorMessage = "Invalid Telegram API URL."
            return
        }

        isUploading = true
        progress = 0
        statusText = "Preparing multipart upload..."
        speedText = ""
        errorMessage = nil
        successMessage = nil
        startTime = Date()

        let fileName = videoURL.lastPathComponent
        let boundary = "Boundary-\(UUID().uuidString)"
        let tempBodyURL = FileManager.default.temporaryDirectory.appendingPathComponent("tg_upload_\(UUID().uuidString).multipart")
        self.tempMultipartURL = tempBodyURL

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            do {
                try Self.writeMultipartFile(
                    to: tempBodyURL,
                    boundary: boundary,
                    fields: [
                        ("chat_id", target),
                        ("caption", caption),
                        ("parse_mode", "HTML"),
                        ("supports_streaming", supportsStreaming ? "true" : "false"),
                        ("protect_content", protectContent ? "true" : "false"),
                        ("disable_notification", disableNotification ? "true" : "false")
                    ],
                    fileFieldName: "video",
                    fileURL: videoURL
                )

                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.timeoutInterval = 600
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 60
                config.timeoutIntervalForResource = 900
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

                await MainActor.run {
                    self.activeSession = session
                    self.statusText = "Uploading \(fileName)..."
                }

                let task = session.uploadTask(with: request, fromFile: tempBodyURL) { data, response, error in
                    try? FileManager.default.removeItem(at: tempBodyURL)

                    Task { @MainActor in
                        self.isUploading = false
                        if let error = error {
                            self.errorMessage = error.localizedDescription
                            self.queueHistory.insert(
                                UploadQueueItem(fileName: fileName, targetChat: target, caption: caption, scheduledAt: nil, status: "Failed: \(error.localizedDescription)", isCompleted: false, isFailed: true),
                                at: 0
                            )
                            return
                        }

                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let ok = json["ok"] as? Bool ?? false
                            if ok {
                                self.progress = 1.0
                                self.statusText = "100% Uploaded!"
                                self.successMessage = "Published '\(fileName)' to \(target)!"
                                self.queueHistory.insert(
                                    UploadQueueItem(fileName: fileName, targetChat: target, caption: caption, scheduledAt: nil, status: "Published to \(target)", isCompleted: true, isFailed: false),
                                    at: 0
                                )
                            } else {
                                let desc = json["description"] as? String ?? "Telegram error (HTTP \(statusCode))"
                                self.errorMessage = desc
                                self.queueHistory.insert(
                                    UploadQueueItem(fileName: fileName, targetChat: target, caption: caption, scheduledAt: nil, status: "Error: \(desc)", isCompleted: false, isFailed: true),
                                    at: 0
                                )
                            }
                        } else {
                            self.errorMessage = "Upload response error (HTTP \(statusCode)). Note: Standard Telegram Bot API upload limit is 50 MB."
                        }
                    }
                }

                await MainActor.run {
                    self.activeTask = task
                }
                task.resume()
            } catch {
                await MainActor.run {
                    self.isUploading = false
                    self.errorMessage = "Failed to build upload payload: \(error.localizedDescription)"
                }
            }
        }
    }

    func cancelUpload() {
        activeTask?.cancel()
        isUploading = false
        statusText = "Upload cancelled"
        if let temp = tempMultipartURL {
            try? FileManager.default.removeItem(at: temp)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let elapsed = max(0.1, Date().timeIntervalSince(startTime))
        let speedKBps = (Double(totalBytesSent) / 1024.0) / elapsed
        let sentMB = Double(totalBytesSent) / (1024.0 * 1024.0)
        let totalMB = Double(max(1, totalBytesExpectedToSend)) / (1024.0 * 1024.0)
        let pct = totalBytesExpectedToSend > 0 ? Double(totalBytesSent) / Double(totalBytesExpectedToSend) : 0

        Task { @MainActor in
            self.progress = min(1.0, max(0.0, pct))
            self.statusText = String(format: "%d%% (%.1f MB / %.1f MB)", Int(pct * 100), sentMB, totalMB)
            self.speedText = speedKBps >= 1024
                ? String(format: "%.2f MB/s", speedKBps / 1024.0)
                : String(format: "%.0f KB/s", speedKBps)
        }
    }

    private static func writeMultipartFile(
        to destination: URL,
        boundary: String,
        fields: [(String, String)],
        fileFieldName: String,
        fileURL: URL
    ) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        func appendString(_ str: String) {
            if let data = str.data(using: .utf8) {
                handle.write(data)
            }
        }

        for (name, value) in fields {
            if value.isEmpty && name == "caption" { continue }
            appendString("--\(boundary)\r\n")
            appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            appendString("\(value)\r\n")
        }

        let filename = fileURL.lastPathComponent
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: video/mp4\r\n\r\n")

        let readHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? readHandle.close() }
        while true {
            let chunk = readHandle.readData(ofLength: 256 * 1024)
            if chunk.isEmpty { break }
            handle.write(chunk)
        }

        appendString("\r\n--\(boundary)--\r\n")
    }

    static func inspectVideo(url: URL) async -> VideoAssetMetadata {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let asset = AVURLAsset(url: url)
        var durSec: Double = 0
        if let d = try? await asset.load(.duration) {
            let s = CMTimeGetSeconds(d)
            if s.isFinite { durSec = s }
        }

        var resText = "HD Video"
        if let tracks = try? await asset.loadTracks(withMediaType: .video), let first = tracks.first {
            if let naturalSize = try? await first.load(.naturalSize),
               let transform = try? await first.load(.preferredTransform) {
                let transformed = naturalSize.applying(transform)
                let w = Int(abs(transformed.width))
                let h = Int(abs(transformed.height))
                if w > 0 && h > 0 {
                    resText = "\(w)×\(h)"
                }
            }
        }

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 320)
        let thumbTime = CMTime(seconds: min(2.0, durSec * 0.2), preferredTimescale: 600)
        var thumb: UIImage? = nil
        if let cg = try? gen.copyCGImage(at: thumbTime, actualTime: nil) {
            thumb = UIImage(cgImage: cg)
        }

        return VideoAssetMetadata(
            url: url,
            fileName: url.lastPathComponent,
            fileSizeBytes: size,
            durationSeconds: durSec,
            resolutionText: resText,
            thumbnail: thumb
        )
    }

    static func discoverChats(botToken: String) async -> [DiscoveredTelegramChat] {
        let token = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              let url = URL(string: "https://api.telegram.org/bot\(token)/getUpdates?limit=50") else {
            return []
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url))
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ok = json["ok"] as? Bool, ok,
                  let results = json["result"] as? [[String: Any]] else {
                return []
            }
            var seen: [String: DiscoveredTelegramChat] = [:]
            for item in results {
                let msg = (item["channel_post"] as? [String: Any])
                    ?? (item["message"] as? [String: Any])
                    ?? (item["my_chat_member"] as? [String: Any])
                if let chat = msg?["chat"] as? [String: Any] {
                    let idNum = (chat["id"] as? NSNumber)?.stringValue ?? ""
                    let username = chat["username"] as? String
                    let chatKey = (username != nil && !(username!.isEmpty)) ? "@\(username!)" : idNum
                    let title = (chat["title"] as? String)
                        ?? (chat["first_name"] as? String)
                        ?? chatKey
                    let type = chat["type"] as? String ?? "chat"
                    if !chatKey.isEmpty {
                        seen[chatKey] = DiscoveredTelegramChat(id: chatKey, title: title, type: type)
                    }
                }
            }
            return Array(seen.values).sorted { $0.title < $1.title }
        } catch {
            return []
        }
    }
}
