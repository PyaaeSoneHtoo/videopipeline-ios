import SwiftUI

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

    func startDownload(from urlString: String) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Please enter a valid HTTP/HTTPS link."
            return
        }

        let lastSeg = url.lastPathComponent
        if !lastSeg.isEmpty && lastSeg.contains(".") {
            targetFileName = lastSeg
        } else {
            targetFileName = "telegram_video_\(Int(Date().timeIntervalSince1970)).mp4"
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
    @StateObject private var downloader = StreamingDownloadManager()
    @State private var urlInput: String = ""

    var body: some View {
        ZStack {
            AppTheme.bgDark.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Telegram / Direct Video Link", systemImage: "paperplane.fill")
                            .font(.headline)
                            .foregroundColor(AppTheme.cyan)

                        Text("Paste a direct video download link or stream URL. Downloaded files appear directly in Apple Files under On My iPhone → Video Pipeline → Downloads.")
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
}
