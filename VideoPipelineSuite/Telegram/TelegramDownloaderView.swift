import SwiftUI
import AVKit
import UIKit

struct PreviewVideoItem: Identifiable {
    let id = UUID()
    let url: URL
}

final class DirectLinkDownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
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

    func startDownload(from urlString: String) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Please enter a valid HTTP/HTTPS link."
            return
        }

        let lastSeg = url.lastPathComponent
        targetFileName = (!lastSeg.isEmpty && lastSeg.contains("."))
            ? lastSeg
            : "video_\(Int(Date().timeIntervalSince1970)).mp4"

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

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
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

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
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
        case channels = "Channels"
        case link = "Post / Link"
        case files = "Downloads"
        var id: String { rawValue }
    }

    @ObservedObject private var mtproto = TelegramMTProtoManager.shared
    @StateObject private var directDownloader = DirectLinkDownloadManager()

    @State private var activeTab: DownloadTab = .channels
    @State private var selectedChat: MTProtoChatItem? = nil
    @State private var channelSearch: String = ""
    @State private var videoSearch: String = ""
    @State private var linkInput: String = ""

    @State private var downloadedFiles: [URL] = []
    @State private var previewItem: PreviewVideoItem? = nil

    private var filteredChats: [MTProtoChatItem] {
        let q = channelSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return mtproto.chats }
        return mtproto.chats.filter { $0.title.lowercased().contains(q) }
    }

    private var filteredVideos: [MTProtoVideoMessage] {
        let q = videoSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return mtproto.channelVideos }
        return mtproto.channelVideos.filter {
            $0.fileName.lowercased().contains(q) || $0.caption.lowercased().contains(q)
        }
    }

    private var isAnyDownloadActive: Bool {
        mtproto.isDownloading || directDownloader.isDownloading
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
                            Text("MTProto Downloader")
                                .font(.headline)
                                .foregroundColor(AppTheme.textPrimary)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(mtproto.isAuthorized ? AppTheme.emerald : AppTheme.amber)
                                    .frame(width: 7, height: 7)
                                Text(mtproto.isAuthorized
                                     ? "Connected: \(mtproto.connectedUserName)"
                                     : "Tap Key Icon to Login Telegram MTProto")
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.textSecondary)
                                    .lineLimit(1)
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
                        // Active MTProto or Direct Transfer Monitor
                        if mtproto.isDownloading || mtproto.lastDownloadedURL != nil || mtproto.downloadError != nil {
                            transferCard(
                                filename: mtproto.downloadFileName,
                                progress: mtproto.downloadProgress,
                                detail: mtproto.downloadError ?? mtproto.downloadDetailText,
                                speed: mtproto.downloadSpeedText,
                                isDownloading: mtproto.isDownloading,
                                isError: mtproto.downloadError != nil,
                                savedURL: mtproto.lastDownloadedURL,
                                onCancel: { mtproto.cancelActiveDownload() }
                            )
                        }

                        if directDownloader.isDownloading || directDownloader.savedFileURL != nil || directDownloader.errorMessage != nil {
                            transferCard(
                                filename: directDownloader.filename,
                                progress: directDownloader.progress,
                                detail: directDownloader.errorMessage ?? directDownloader.percentText,
                                speed: directDownloader.speedText,
                                isDownloading: directDownloader.isDownloading,
                                isError: directDownloader.errorMessage != nil,
                                savedURL: directDownloader.savedFileURL,
                                onCancel: { directDownloader.cancelDownload() }
                            )
                        }

                        switch activeTab {
                        case .channels:
                            channelsPanel
                        case .link:
                            postAndDirectLinkPanel
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
            if mtproto.isAuthorized && mtproto.chats.isEmpty {
                mtproto.loadUserChats()
            }
        }
        .onChange(of: mtproto.lastDownloadedURL) { _ in
            refreshDownloadedFiles()
        }
        .onChange(of: directDownloader.savedFileURL) { _ in
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

    // MARK: - Transfer Progress Card
    private func transferCard(
        filename: String,
        progress: Double,
        detail: String,
        speed: String,
        isDownloading: Bool,
        isError: Bool,
        savedURL: URL?,
        onCancel: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(AppTheme.surfaceCardBorder, lineWidth: 4)
                        .frame(width: 44, height: 44)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(isError ? AppTheme.danger : AppTheme.emerald, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 44, height: 44)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundColor(AppTheme.textPrimary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(filename.isEmpty ? "MTProto Transfer" : filename)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(isError ? AppTheme.danger : AppTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if isDownloading {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(AppTheme.danger)
                    }
                }
            }

            if isDownloading {
                ProgressView(value: progress)
                    .tint(AppTheme.cyan)
                HStack {
                    Label("MTProto High-Speed Stream", systemImage: "bolt.fill")
                        .font(.caption2)
                        .foregroundColor(AppTheme.textMuted)
                    Spacer()
                    Text(speed)
                        .font(.caption.monospacedDigit().bold())
                        .foregroundColor(AppTheme.emerald)
                }
            }

            if let saved = savedURL, !isDownloading {
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

    // MARK: - Tab 1: Personal Telegram Channels (MTProto)
    private var channelsPanel: some View {
        VStack(spacing: 14) {
            if !mtproto.isAuthorized {
                VStack(spacing: 12) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 44))
                        .foregroundColor(AppTheme.emerald)
                    Text("Log In to Telegram MTProto")
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Sign in with your phone number & OTP to browse all your Telegram channels — including save/forward-restricted channels — and download videos up to 2 GB.")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    NavigationLink(destination: ApiSetupView()) {
                        Label("Login Telegram (Phone + OTP)", systemImage: "paperplane.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppTheme.emerald)
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .pipelineCard()
            } else if let activeChat = selectedChat {
                // Inside selected channel: list videos
                HStack {
                    Button {
                        selectedChat = nil
                        videoSearch = ""
                    } label: {
                        Label("All Channels", systemImage: "chevron.left")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppTheme.cyan)
                    }
                    Spacer()
                    if activeChat.isProtected {
                        Text("🔓 Restricted Bypass Ready")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.emerald.opacity(0.18))
                            .foregroundColor(AppTheme.emerald)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppTheme.textMuted)
                    TextField("Search videos in \(activeChat.title)...", text: $videoSearch)
                        .foregroundColor(AppTheme.textPrimary)
                        .font(.subheadline)
                }
                .padding(10)
                .background(AppTheme.surfaceCardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.surfaceCardBorder, lineWidth: 1))

                if mtproto.isLoadingMessages {
                    ProgressView("Loading channel videos...")
                        .tint(AppTheme.cyan)
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.vertical, 28)
                } else if filteredVideos.isEmpty {
                    Text("No video messages found in the recent history of \(activeChat.title).")
                        .font(.caption)
                        .foregroundColor(AppTheme.textMuted)
                        .padding(.vertical, 24)
                } else {
                    ForEach(filteredVideos) { item in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill((item.isProtected ? AppTheme.emerald : AppTheme.cyan).opacity(0.16))
                                    .frame(width: 46, height: 46)
                                Image(systemName: item.isProtected ? "lock.open.fill" : "film.fill")
                                    .foregroundColor(item.isProtected ? AppTheme.emerald : AppTheme.cyan)
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
                                    if item.isProtected {
                                        Text("Restricted")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(AppTheme.emerald.opacity(0.18))
                                            .foregroundColor(AppTheme.emerald)
                                            .clipShape(Capsule())
                                    }
                                }
                                if !item.caption.isEmpty {
                                    Text(item.caption)
                                        .font(.caption2)
                                        .foregroundColor(AppTheme.textSecondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Button {
                                mtproto.startVideoDownload(item)
                            } label: {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(AppTheme.emerald)
                            }
                            .disabled(isAnyDownloadActive)
                        }
                        .pipelineCard(cornerRadius: 14, padding: 12)
                    }
                }
            } else {
                // Channel / Chat List
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AppTheme.textMuted)
                        TextField("Filter channels & groups...", text: $channelSearch)
                            .foregroundColor(AppTheme.textPrimary)
                            .font(.subheadline)
                    }
                    .padding(10)
                    .background(AppTheme.surfaceCardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.surfaceCardBorder, lineWidth: 1))

                    Button {
                        mtproto.loadUserChats()
                    } label: {
                        if mtproto.isLoadingChats {
                            ProgressView().tint(.black).frame(width: 40, height: 40)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(width: 40, height: 40)
                        }
                    }
                    .background(AppTheme.emerald)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if filteredChats.isEmpty {
                    Text(mtproto.isLoadingChats ? "Loading your Telegram channels..." : "Tap refresh to load your Telegram channels & groups.")
                        .font(.caption)
                        .foregroundColor(AppTheme.textMuted)
                        .padding(.vertical, 24)
                } else {
                    ForEach(filteredChats) { chat in
                        Button {
                            selectedChat = chat
                            mtproto.loadVideosForChat(chat)
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill((chat.isProtected ? AppTheme.emerald : AppTheme.primary).opacity(0.18))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: chat.isChannel ? "megaphone.fill" : "person.2.fill")
                                        .foregroundColor(chat.isProtected ? AppTheme.emerald : AppTheme.primaryLight)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(chat.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(AppTheme.textPrimary)
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(chat.isChannel ? "Channel" : "Chat / Group")
                                            .font(.caption2)
                                            .foregroundColor(AppTheme.textSecondary)
                                        if chat.isProtected {
                                            Text("🔓 Restricted Supported")
                                                .font(.caption2.bold())
                                                .foregroundColor(AppTheme.emerald)
                                        }
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundColor(AppTheme.textMuted)
                            }
                            .pipelineCard(cornerRadius: 14, padding: 12)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tab 2: Telegram Post Link (t.me/...) or Direct URL
    private var postAndDirectLinkPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Telegram Post Link or Direct URL", systemImage: "link.circle.fill")
                    .font(.headline)
                    .foregroundColor(AppTheme.cyan)
                Spacer()
                Button {
                    if let clip = UIPasteboard.general.string {
                        linkInput = clip
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

            Text("Paste a Telegram post link (https://t.me/channel/123 or private https://t.me/c/...) to download via MTProto — even from save-restricted channels — or paste any direct .mp4 link.")
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary)

            HStack {
                TextField("https://t.me/channel/123 or direct .mp4", text: $linkInput)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(AppTheme.textPrimary)
                if !linkInput.isEmpty {
                    Button { linkInput = "" } label: {
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
                let clean = linkInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.lowercased().contains("t.me/") || clean.lowercased().contains("telegram.me/") {
                    mtproto.downloadFromTelegramLink(clean)
                } else {
                    directDownloader.startDownload(from: clean)
                }
            } label: {
                Label("Download Video", systemImage: "arrow.down.to.line.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle(color: AppTheme.emerald))
            .disabled(linkInput.trimmingCharacters(in: .whitespaces).isEmpty || isAnyDownloadActive)
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
                    Text("Videos downloaded via MTProto or Direct Links appear here for instant AVPlayer preview & sharing.")
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
}
