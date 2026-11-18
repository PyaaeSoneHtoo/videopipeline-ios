import SwiftUI
import AVKit
import UIKit

struct TelegramBotMediaItem: Identifiable {
    let id: String
    let fileId: String
    let fileName: String
    let caption: String
    let sizeBytes: Int64
}

struct PreviewVideoItem: Identifiable {
    let id = UUID()
    let url: URL
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
            self.speedText = speedKBps >= 1024
                ? String(format: "%.2f MB/s", speedKBps / 1024.0)
                : String(format: "%.0f KB/s", speedKBps)
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
                self.percentText = "100% Completed"
                self.speedText = "Saved to Files → Downloads"
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
    private enum DownloadTab: String, CaseIterable, Identifiable {
        case inbox = "Bot Inbox"
        case direct = "Direct URL"
        case files = "Downloads"
        var id: String { rawValue }
    }

    @ObservedObject private var api = ApiSettingsStore.shared
    @StateObject private var downloader = StreamingDownloadManager()

    @State private var activeTab: DownloadTab = .inbox
    @State private var urlInput: String = ""
    @State private var searchQuery: String = ""

    @State private var botMediaItems: [TelegramBotMediaItem] = []
    @State private var isLoadingBotInbox: Bool = false
    @State private var botStatusNote: String? = nil

    @State private var downloadedFiles: [URL] = []
    @State private var previewItem: PreviewVideoItem? = nil

    private var filteredBotItems: [TelegramBotMediaItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return botMediaItems }
        return botMediaItems.filter {
            $0.fileName.lowercased().contains(q) || $0.caption.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            AppTheme.bgDark.ignoresSafeArea()

            VStack(spacing: 0) {
                // Studio Header Bar
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(colors: [AppTheme.cyan, AppTheme.emerald], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 44, height: 44)
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Downloader Studio")
                                .font(.headline)
                                .foregroundColor(AppTheme.textPrimary)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(api.isTelegramConfigured ? AppTheme.emerald : AppTheme.amber)
                                    .frame(width: 7, height: 7)
                                Text(api.telegramConnectedUsername.isEmpty
                                     ? (api.isTelegramConfigured ? "Telegram Configured" : "Tap Key Icon to Login Telegram")
                                     : "Connected: @\(api.telegramConnectedUsername)")
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }

                        Spacer()

                        NavigationLink(destination: ApiSetupView()) {
                            Image(systemName: "key.fill")
                                .font(.caption.bold())
                                .foregroundColor(AppTheme.amber)
                                .padding(9)
                                .background(AppTheme.surfaceCardElevated)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(AppTheme.surfaceCardBorder, lineWidth: 1))
                        }
                    }

                    Picker("Download Mode", selection: $activeTab) {
                        ForEach(DownloadTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.surfaceCard)
                .overlay(
                    Rectangle().fill(AppTheme.surfaceCardBorder).frame(height: 1),
                    alignment: .bottom
                )

                ScrollView {
                    VStack(spacing: 16) {
                        // Active Live Transfer Monitor (visible across all tabs while downloading)
                        if downloader.isDownloading || downloader.savedFileURL != nil || downloader.errorMessage != nil {
                            activeTransferCard
                        }

                        switch activeTab {
                        case .inbox:
                            botInboxPanel
                        case .direct:
                            directLinkPanel
                        case .files:
                            downloadedFilesPanel
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Downloader Studio")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshDownloadedFiles()
            if !api.hasTelegramBot {
                activeTab = .direct
            }
        }
        .onChange(of: downloader.savedFileURL) { _ in
            refreshDownloadedFiles()
        }
        .sheet(item: $previewItem) { item in
            NavigationStack {
                VideoPlayer(player: AVPlayer(url: item.url))
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(item.url.lastPathComponent)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { previewItem = nil }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Live Transfer Card
    private var activeTransferCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(AppTheme.surfaceCardBorder, lineWidth: 4)
                        .frame(width: 44, height: 44)
                    Circle()
                        .trim(from: 0, to: downloader.progress)
                        .stroke(
                            downloader.errorMessage != nil ? AppTheme.danger : AppTheme.emerald,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 44, height: 44)
                    Text("\(Int(downloader.progress * 100))%")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundColor(AppTheme.textPrimary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(downloader.filename.isEmpty ? "Download Transfer" : downloader.filename)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    Text(downloader.errorMessage ?? downloader.percentText)
                        .font(.caption)
                        .foregroundColor(downloader.errorMessage != nil ? AppTheme.danger : AppTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if downloader.isDownloading {
                    Button {
                        downloader.cancelDownload()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(AppTheme.danger)
                    }
                }
            }

            if downloader.isDownloading {
                ProgressView(value: downloader.progress)
                    .tint(AppTheme.cyan)
                HStack {
                    Label("Streaming to Apple Files", systemImage: "bolt.fill")
                        .font(.caption2)
                        .foregroundColor(AppTheme.textMuted)
                    Spacer()
                    Text(downloader.speedText)
                        .font(.caption.monospacedDigit().bold())
                        .foregroundColor(AppTheme.emerald)
                }
            }

            if let saved = downloader.savedFileURL, !downloader.isDownloading {
                HStack(spacing: 10) {
                    Button {
                        previewItem = PreviewVideoItem(url: saved)
                    } label: {
                        Label("Play Preview", systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(AppTheme.primary.opacity(0.2))
                            .foregroundColor(AppTheme.primaryLight)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    ShareLink(item: saved) {
                        Label("Share / Save", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(AppTheme.emerald)
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .pipelineCard()
    }

    // MARK: - Tab 1: Telegram Bot Inbox
    private var botInboxPanel: some View {
        VStack(spacing: 14) {
            if !api.hasTelegramBot {
                VStack(spacing: 12) {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.system(size: 46))
                        .foregroundColor(AppTheme.cyan)
                    Text("Connect Your Telegram Bot")
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Log in with your Telegram Bot Token to sync & download videos sent or forwarded to your bot straight to your iPhone.")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    NavigationLink(destination: ApiSetupView()) {
                        Label("Open Telegram Login & API Setup", systemImage: "key.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppTheme.primary)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .pipelineCard()
            } else {
                // Search & Sync Bar
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AppTheme.textMuted)
                        TextField("Filter by filename or caption...", text: $searchQuery)
                            .foregroundColor(AppTheme.textPrimary)
                            .font(.subheadline)
                    }
                    .padding(10)
                    .background(AppTheme.surfaceCardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.surfaceCardBorder, lineWidth: 1))

                    Button {
                        fetchBotMediaInbox()
                    } label: {
                        if isLoadingBotInbox {
                            ProgressView().tint(.black)
                                .frame(width: 40, height: 40)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(width: 40, height: 40)
                        }
                    }
                    .background(AppTheme.emerald)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .disabled(isLoadingBotInbox)
                }

                if let note = botStatusNote {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if filteredBotItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 34))
                            .foregroundColor(AppTheme.textMuted)
                        Text("Tap Refresh to Sync Bot Videos")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        Text("Forward or send any video to @\(api.telegramConnectedUsername.isEmpty ? "your_bot" : api.telegramConnectedUsername) on Telegram, then tap Sync.")
                            .font(.caption)
                            .foregroundColor(AppTheme.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .pipelineCard()
                } else {
                    ForEach(filteredBotItems) { item in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(AppTheme.cyan.opacity(0.16))
                                    .frame(width: 46, height: 46)
                                Image(systemName: "film.fill")
                                    .foregroundColor(AppTheme.cyan)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.fileName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(String(format: "%.1f MB", Double(item.sizeBytes) / (1024 * 1024)))
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.primary.opacity(0.2))
                                        .foregroundColor(AppTheme.primaryLight)
                                        .clipShape(Capsule())
                                    if !item.caption.isEmpty {
                                        Text(item.caption)
                                            .font(.caption2)
                                            .foregroundColor(AppTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            Spacer()
                            Button {
                                downloadTelegramBotFile(item)
                            } label: {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(AppTheme.emerald)
                            }
                            .disabled(downloader.isDownloading)
                        }
                        .pipelineCard(cornerRadius: 14, padding: 12)
                    }
                }
            }
        }
    }

    // MARK: - Tab 2: Direct Link Stream Downloader
    private var directLinkPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("High-Speed Direct Link", systemImage: "link.circle.fill")
                    .font(.headline)
                    .foregroundColor(AppTheme.cyan)
                Spacer()
                Button {
                    if let clip = UIPasteboard.general.string {
                        urlInput = clip
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.surfaceCardElevated)
                        .foregroundColor(AppTheme.primaryLight)
                        .clipShape(Capsule())
                }
            }

            Text("Paste any direct video or stream download link. Saved directly into Apple Files → On My iPhone → Video Pipeline → Downloads.")
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary)

            HStack {
                TextField("https://example.com/episode01.mp4", text: $urlInput)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(AppTheme.textPrimary)
                if !urlInput.isEmpty {
                    Button {
                        urlInput = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.textMuted)
                    }
                }
            }
            .padding(14)
            .background(AppTheme.surfaceCardElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.surfaceCardBorder, lineWidth: 1))

            Button {
                downloader.startDownload(from: urlInput)
            } label: {
                Label("Start High-Speed Download", systemImage: "arrow.down.to.line.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle(color: AppTheme.cyan))
            .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty || downloader.isDownloading)
        }
        .pipelineCard()
    }

    // MARK: - Tab 3: Local Downloads Manager
    private var downloadedFilesPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Saved Videos (\(downloadedFiles.count))")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button {
                    refreshDownloadedFiles()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.cyan)
                }
            }

            if downloadedFiles.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 38))
                        .foregroundColor(AppTheme.textMuted)
                    Text("No Downloaded Videos Yet")
                        .font(.headline)
                        .foregroundColor(AppTheme.textSecondary)
                    Text("Videos downloaded from Telegram Bot or Direct Links will appear here for instant playback & sharing.")
                        .font(.caption)
                        .foregroundColor(AppTheme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .pipelineCard()
            } else {
                ForEach(downloadedFiles, id: \.self) { fileURL in
                    HStack(spacing: 12) {
                        Button {
                            previewItem = PreviewVideoItem(url: fileURL)
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(AppTheme.primary.opacity(0.18))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "play.fill")
                                    .foregroundColor(AppTheme.primaryLight)
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(fileURL.lastPathComponent)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(AppTheme.textPrimary)
                                .lineLimit(1)
                            Text(fileSizeString(for: fileURL))
                                .font(.caption2)
                                .foregroundColor(AppTheme.textSecondary)
                        }

                        Spacer()

                        ShareLink(item: fileURL) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.subheadline)
                                .foregroundColor(AppTheme.emerald)
                                .padding(8)
                                .background(AppTheme.emerald.opacity(0.15))
                                .clipShape(Circle())
                        }

                        Button {
                            try? FileManager.default.removeItem(at: fileURL)
                            refreshDownloadedFiles()
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline)
                                .foregroundColor(AppTheme.danger)
                                .padding(8)
                                .background(AppTheme.danger.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                    .pipelineCard(cornerRadius: 14, padding: 12)
                }
            }
        }
    }

    // MARK: - Helpers
    private func refreshDownloadedFiles() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dlDir = docs.appendingPathComponent("Downloads", isDirectory: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: dlDir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) {
            downloadedFiles = files.sorted { $0.lastPathComponent > $1.lastPathComponent }
        } else {
            downloadedFiles = []
        }
    }

    private func fileSizeString(for url: URL) -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let mb = Double(size) / (1024 * 1024)
        return mb >= 1.0 ? String(format: "%.1f MB", mb) : String(format: "%.0f KB", Double(size) / 1024.0)
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
                    botStatusNote = found.isEmpty ? "No recent videos in Bot inbox. Forward a video to your bot, then tap Sync." : "Synced \(found.count) video(s) from Telegram Bot."
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

        botStatusNote = "Resolving Telegram file path..."
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
                    let desc = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["description"] as? String ?? "Telegram Bot API supports direct downloads up to 20 MB."
                    botStatusNote = "Telegram error: \(desc)"
                }
            } catch {
                botStatusNote = "Error: \(error.localizedDescription)"
            }
        }
    }
}
