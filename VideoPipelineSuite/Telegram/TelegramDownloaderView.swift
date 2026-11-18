import SwiftUI

struct TelegramBotMediaItem: Identifiable {
    let id: String
    let fileId: String
    let fileName: String
    let caption: String
    let sizeBytes: Int64
}

final class StreamingDownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var isDownloading: Bool = false
    @Published var progress: Double = 0
    @Published var filename: String = ""
    @Published var percentText: String = "0%"
    @Published var speedText: String = ""
    @Published var savedFileURL: URL? = nil
    @Published var errorMessage: String? = nil

    private var startTime: Date = Date()
    private var targetFileName: String = "video.mp4"
    private var session: URLSession?
    private var currentTask: URLSessionDownloadTask?

    func startDownload(from urlString: String, customFileName: String? = nil) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Please enter a valid HTTP/HTTPS link."
            return
        }

        if let custom = customFileName, !custom.isEmpty {
            targetFileName = custom
        } else {
            let lastSeg = url.lastPathComponent
            if !lastSeg.isEmpty && lastSeg.contains(".") {
                targetFileName = lastSeg
            } else {
                targetFileName = "telegram_video_\(Int(Date().timeIntervalSince1970)).mp4"
            }
        }

        filename = targetFileName
        isDownloading = true
        progress = 0
        percentText = "Connecting..."
        speedText = ""
        savedFileURL = nil
        errorMessage = nil
        startTime = Date()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        let urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        session = urlSession

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let task = urlSession.downloadTask(with: request)
        currentTask = task
        task.resume()
    }

    func cancelDownload() {
        currentTask?.cancel()
        isDownloading = false
        speedText = "Cancelled"
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let elapsed = max(0.1, Date().timeIntervalSince(startTime))
        let speedKBps = (Double(totalBytesWritten) / 1024.0) / elapsed
        let writtenMB = Double(totalBytesWritten) / (1024.0 * 1024.0)

        Task { @MainActor in
            if totalBytesExpectedToWrite > 0 {
                let pct = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                let totalMB = Double(totalBytesExpectedToWrite) / (1024.0 * 1024.0)
                self.progress = min(1.0, max(0.0, pct))
                self.percentText = String(format: "%d%% (%.1f MB / %.1f MB)", Int(pct * 100), writtenMB, totalMB)
            } else {
                self.percentText = String(format: "Downloaded %.1f MB", writtenMB)
            }
            self.speedText = String(format: "%.1f KB/s", speedKBps)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsDir = docsDir.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)

        let destURL = downloadsDir.appendingPathComponent(targetFileName)
        try? FileManager.default.removeItem(at: destURL)

        do {
            try FileManager.default.moveItem(at: location, to: destURL)
            Task { @MainActor in
                self.isDownloading = false
                self.progress = 1.0
                self.percentText = "100% - Download Completed!"
                self.speedText = "Saved in Files -> Video Pipeline -> Downloads"
                self.savedFileURL = destURL
            }
        } catch {
            Task { @MainActor in
                self.isDownloading = false
                self.errorMessage = "File save failed: \(error.localizedDescription)"
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.isDownloading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
}

struct TelegramDownloaderView: View {
    @ObservedObject private var api = ApiSettingsStore.shared
    @StateObject private var downloader = StreamingDownloadManager()
    @State private var urlInput: String = ""

    @State private var botMediaItems: [TelegramBotMediaItem] = []
    @State private var isLoadingBotInbox: Bool = false
    @State private var botStatusNote: String? = nil

    var body: some View {
        ZStack {
            AppTheme.bgDark.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Telegram Login / Account Connection Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Telegram Connection", systemImage: "person.badge.key.fill")
                                .font(.headline)
                                .foregroundColor(AppTheme.amber)
                            Spacer()
                            if api.isTelegramConfigured {
                                Text(api.telegramConnectedUsername.isEmpty ? "Configured" : "@\(api.telegramConnectedUsername)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.emerald.opacity(0.2))
                                    .foregroundColor(AppTheme.emerald)
                                    .clipShape(Capsule())
                            } else {
                                Text("Not Logged In")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.danger.opacity(0.18))
                                    .foregroundColor(AppTheme.danger)
                                    .clipShape(Capsule())
                            }
                        }

                        if api.hasTelegramMTProto {
                            Text("MTProto Account: \(api.telegramPhone) (API ID: \(api.telegramApiId))")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary)
                        }

                        HStack(spacing: 10) {
                            NavigationLink(destination: ApiSetupView()) {
                                Label(api.isTelegramConfigured ? "Manage Telegram Login" : "Login Telegram / Import API", systemImage: "gearshape.fill")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.primary)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            if api.hasTelegramBot {
                                Button {
                                    fetchBotMediaInbox()
                                } label: {
                                    if isLoadingBotInbox {
                                        ProgressView().tint(.black)
                                    } else {
                                        Label("Sync Bot Videos", systemImage: "arrow.clockwise")
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(AppTheme.emerald)
                                .foregroundColor(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .disabled(isLoadingBotInbox)
                            }
                        }

                        if let note = botStatusNote {
                            Text(note)
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    .pipelineCard()

                    // Recent Videos Sent to Telegram Bot
                    if !botMediaItems.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Telegram Bot Video Inbox (\(botMediaItems.count))")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(AppTheme.textPrimary)

                            ForEach(botMediaItems) { item in
                                HStack(spacing: 10) {
                                    Image(systemName: "film.fill")
                                        .foregroundColor(AppTheme.cyan)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.fileName)
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(AppTheme.textPrimary)
                                            .lineLimit(1)
                                        Text(String(format: "%.1f MB %@", Double(item.sizeBytes) / (1024 * 1024), item.caption.isEmpty ? "" : "• \(item.caption)"))
                                            .font(.caption2)
                                            .foregroundColor(AppTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Button("Download") {
                                        downloadTelegramBotFile(item)
                                    }
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.cyan)
                                    .foregroundColor(.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .disabled(downloader.isDownloading)
                                }
                                .padding(10)
                                .background(AppTheme.surfaceCardElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .pipelineCard()
                    }

                    // Direct Video / Stream Link Card
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Direct Video / Stream Link", systemImage: "paperplane.fill")
                            .font(.headline)
                            .foregroundColor(AppTheme.cyan)

                        Text("Paste any direct video download URL. Files save to Apple Files under On My iPhone → Video Pipeline → Downloads.")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)

                        TextField("https://example.com/video.mp4", text: $urlInput)
                            .keyboardType(.URL)
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

                        HStack(spacing: 10) {
                            Button {
                                downloader.startDownload(from: urlInput)
                            } label: {
                                Label("Start Download", systemImage: "arrow.down.circle.fill")
                            }
                            .buttonStyle(PrimaryButtonStyle(color: AppTheme.cyan))
                            .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty || downloader.isDownloading)

                            if downloader.isDownloading {
                                Button {
                                    downloader.cancelDownload()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(14)
                                        .background(AppTheme.danger)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                    .pipelineCard()

                    if downloader.isDownloading || !downloader.filename.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(downloader.filename)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(AppTheme.textPrimary)
                                .lineLimit(1)

                            ProgressView(value: downloader.progress)
                                .tint(AppTheme.cyan)

                            HStack {
                                Text(downloader.percentText)
                                    .font(.caption)
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Text(downloader.speedText)
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(AppTheme.emerald)
                            }
                        }
                        .pipelineCard()
                    }

                    if let err = downloader.errorMessage {
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(AppTheme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pipelineCard(cornerRadius: 12, padding: 12)
                    }

                    if let fileURL = downloader.savedFileURL {
                        ShareLink(item: fileURL) {
                            Label("Share or Save to Photos", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.emerald)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Telegram Downloader")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fetchBotMediaInbox() {
        let token = api.telegramBotToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              let url = URL(string: "https://api.telegram.org/bot\(token)/getUpdates?limit=50") else {
            botStatusNote = "Please set your Telegram Bot Token in API Setup first."
            return
        }

        isLoadingBotInbox = true
        botStatusNote = nil

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url))
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let ok = json["ok"] as? Bool, ok,
                   let updates = json["result"] as? [[String: Any]] {
                    var found: [TelegramBotMediaItem] = []
                    for upd in updates.reversed() {
                        let msg = (upd["message"] as? [String: Any]) ?? (upd["channel_post"] as? [String: Any])
                        guard let m = msg else { continue }
                        let caption = m["caption"] as? String ?? ""
                        let msgId = m["message_id"] as? Int ?? Int.random(in: 1...99999)

                        if let video = m["video"] as? [String: Any],
                           let fileId = video["file_id"] as? String {
                            let name = video["file_name"] as? String ?? "tg_video_\(msgId).mp4"
                            let size = (video["file_size"] as? NSNumber)?.int64Value ?? 0
                            found.append(TelegramBotMediaItem(id: "\(msgId)_\(fileId)", fileId: fileId, fileName: name, caption: caption, sizeBytes: size))
                        } else if let doc = m["document"] as? [String: Any],
                                  let fileId = doc["file_id"] as? String {
                            let name = doc["file_name"] as? String ?? "tg_doc_\(msgId).mp4"
                            let size = (doc["file_size"] as? NSNumber)?.int64Value ?? 0
                            found.append(TelegramBotMediaItem(id: "\(msgId)_\(fileId)", fileId: fileId, fileName: name, caption: caption, sizeBytes: size))
                        }
                    }
                    botMediaItems = found
                    botStatusNote = found.isEmpty ? "No recent videos in Bot inbox. Forward or send a video to your bot, then tap Sync." : "Found \(found.count) video(s) from your Telegram Bot."
                } else {
                    botStatusNote = "Could not fetch updates. Check your Bot Token in API Setup."
                }
            } catch {
                botStatusNote = "Sync error: \(error.localizedDescription)"
            }
            isLoadingBotInbox = false
        }
    }

    private func downloadTelegramBotFile(_ item: TelegramBotMediaItem) {
        let token = api.telegramBotToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              let getFileURL = URL(string: "https://api.telegram.org/bot\(token)/getFile?file_id=\(item.fileId)") else { return }

        botStatusNote = "Resolving Telegram file link..."
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: URLRequest(url: getFileURL))
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let ok = json["ok"] as? Bool, ok,
                   let result = json["result"] as? [String: Any],
                   let filePath = result["file_path"] as? String {
                    let downloadURL = "https://api.telegram.org/file/bot\(token)/\(filePath)"
                    botStatusNote = nil
                    downloader.startDownload(from: downloadURL, customFileName: item.fileName)
                } else {
                    let desc = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["description"] as? String ?? "Telegram Bot API supports direct file downloads up to 20 MB."
                    botStatusNote = "Telegram error: \(desc)"
                }
            } catch {
                botStatusNote = "Error: \(error.localizedDescription)"
            }
        }
    }
}
