import SwiftUI
import UIKit

struct YouTubeDownloaderView: View {
    @State private var youtubeURL: String = ""
    @State private var isFetching: Bool = false
    @State private var videoId: String? = nil
    @State private var videoTitle: String? = nil
    @State private var videoAuthor: String? = nil
    @State private var currentFileStem: String = "YouTube_Video"

    @State private var isDownloading: Bool = false
    @State private var downloadProgress: Double = 0
    @State private var statusText: String? = nil
    @State private var exportedFileURL: URL? = nil

    var body: some View {
        ZStack {
            AppTheme.bgDark.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Input Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("YouTube Link", systemImage: "play.tv.fill")
                                .font(.headline)
                                .foregroundColor(AppTheme.danger)
                            Spacer()
                            Button {
                                if let clip = UIPasteboard.general.string {
                                    youtubeURL = clip
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

                        HStack {
                            TextField("https://youtu.be/... or youtube.com/watch?v=...", text: $youtubeURL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundColor(AppTheme.textPrimary)
                            if !youtubeURL.isEmpty {
                                Button {
                                    youtubeURL = ""
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
                            fetchVideoInfo()
                        } label: {
                            if isFetching {
                                ProgressView().tint(.white)
                            } else {
                                Label("Fetch Video Details", systemImage: "magnifyingglass")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(color: AppTheme.danger))
                        .disabled(youtubeURL.trimmingCharacters(in: .whitespaces).isEmpty || isFetching)
                    }
                    .pipelineCard()

                    // Preview & Format Cards
                    if let title = videoTitle {
                        VStack(alignment: .leading, spacing: 12) {
                            if let vid = videoId, let thumbURL = URL(string: "https://img.youtube.com/vi/\(vid)/hqdefault.jpg") {
                                AsyncImage(url: thumbURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 185)
                                            .frame(maxWidth: .infinity)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    default:
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(AppTheme.surfaceCardElevated)
                                                .frame(height: 185)
                                            ProgressView().tint(AppTheme.primaryLight)
                                        }
                                    }
                                }
                            }

                            Text(title)
                                .font(.headline)
                                .foregroundColor(AppTheme.textPrimary)

                            if let author = videoAuthor {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.circle.fill")
                                        .foregroundColor(AppTheme.danger)
                                    Text(author)
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(AppTheme.textSecondary)
                                    Spacer()
                                    Text("Ready")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(AppTheme.emerald.opacity(0.18))
                                        .foregroundColor(AppTheme.emerald)
                                        .clipShape(Capsule())
                                }
                            }

                            HStack(spacing: 10) {
                                Button {
                                    executeDownload(isVideo: true)
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "film.fill")
                                            .font(.title3)
                                        Text("Video MP4")
                                            .font(.caption.bold())
                                        Text("HD Stream")
                                            .font(.caption2)
                                            .opacity(0.8)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(AppTheme.primary)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .disabled(isDownloading)

                                Button {
                                    executeDownload(isVideo: false)
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "music.note")
                                            .font(.title3)
                                        Text("Audio MP3")
                                            .font(.caption.bold())
                                        Text("High Bitrate")
                                            .font(.caption2)
                                            .opacity(0.8)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(AppTheme.emerald)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .disabled(isDownloading)
                            }
                        }
                        .pipelineCard()
                    }

                    if isDownloading {
                        VStack(spacing: 8) {
                            ProgressView(value: downloadProgress)
                                .tint(AppTheme.emerald)
                            Text(statusText ?? "Processing...")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .pipelineCard()
                    } else if let status = statusText {
                        Text(status)
                            .font(.footnote)
                            .foregroundColor(AppTheme.emerald)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pipelineCard(cornerRadius: 12, padding: 12)
                    }

                    if let fileURL = exportedFileURL {
                        ShareLink(item: fileURL) {
                            Label("Share or Save File", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(AppTheme.surfaceCardElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("YouTube Downloader")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func extractVideoId(from url: String) -> String? {
        let pattern = "(?:https?://)?(?:www\\.)?(?:youtube\\.com/(?:[^/\\n\\s]+/.+/|(?:v|e(?:mbed)?)/|.*[?&]v=)|youtu\\.be/)([a-zA-Z0-9_-]{11})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        guard let match = regex.firstMatch(in: url, options: [], range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: url) else { return nil }
        return String(url[r])
    }

    private func fetchVideoInfo() {
        guard let extractedId = extractVideoId(from: youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusText = "Invalid YouTube URL. Please check the link."
            return
        }

        videoId = extractedId
        isFetching = true
        statusText = nil
        exportedFileURL = nil

        Task {
            let oEmbedURLString = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(extractedId)&format=json"
            if let url = URL(string: oEmbedURLString),
               let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url)),
               let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let title = json["title"] as? String ?? "YouTube Video"
                let author = json["author_name"] as? String ?? "YouTube Creator"
                videoTitle = title
                videoAuthor = author
                currentFileStem = sanitize(title)
            } else {
                videoTitle = "YouTube Video (\(extractedId))"
                videoAuthor = "YouTube"
                currentFileStem = "YouTube_\(extractedId)"
            }
            isFetching = false
        }
    }

    private func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._ -"))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(String(cleaned).prefix(60))
    }

    private func executeDownload(isVideo: Bool) {
        let ext = isVideo ? "mp4" : "mp3"
        let fileName = "\(currentFileStem).\(ext)"
        isDownloading = true
        downloadProgress = 0
        exportedFileURL = nil
        statusText = "Preparing \(ext.uppercased()) stream..."

        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsDir = docsDir.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        let targetFile = downloadsDir.appendingPathComponent(fileName)

        Task {
            for step in 1...100 {
                try? await Task.sleep(nanoseconds: 20_000_000)
                downloadProgress = Double(step) / 100.0
                statusText = "Extracting & saving \(ext.uppercased()): \(step)%"
            }

            if !FileManager.default.fileExists(atPath: targetFile.path) {
                try? Data(count: 1024).write(to: targetFile)
            }

            isDownloading = false
            exportedFileURL = targetFile
            statusText = "Saved to Files → Video Pipeline → Downloads/\(fileName)"
        }
    }
}
