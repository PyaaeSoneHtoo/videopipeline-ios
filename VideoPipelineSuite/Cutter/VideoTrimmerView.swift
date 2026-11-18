import SwiftUI
import AVKit
import Photos
import UniformTypeIdentifiers

struct VideoTrimmerView: View {
    @ObservedObject private var api = ApiSettingsStore.shared
    @State private var selectedVideoURL: URL? = nil
    @State private var selectedVideoName: String = "No video selected"
    @State private var durationText: String = "Duration: --:--"
    @State private var cutSecondsText: String = "5.0"
    @State private var player: AVPlayer? = nil
    @State private var showFilePicker: Bool = false

    @State private var isScanningAI: Bool = false
    @State private var aiProvider: AIProvider = ApiSettingsStore.shared.preferredProvider
    @State private var isTrimming: Bool = false
    @State private var trimProgress: Double = 0
    @State private var statusMessage: String? = nil
    @State private var outputFileURL: URL? = nil
    @State private var savedToPhotosMessage: String? = nil

    var body: some View {
        ZStack {
            AppTheme.bgDark.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Video Preview Player
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black)
                            .frame(height: 220)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(AppTheme.surfaceCardBorder, lineWidth: 1)
                            )

                        if let avPlayer = player {
                            VideoPlayer(player: avPlayer)
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "scissors")
                                    .font(.system(size: 36))
                                    .foregroundColor(AppTheme.primaryLight)
                                Text("Select a video to inspect intro")
                                    .font(.subheadline)
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                    }

                    // File Info & Select Button
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedVideoName)
                                .font(.headline)
                                .foregroundColor(AppTheme.textPrimary)
                                .lineLimit(1)
                            Text(durationText)
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        Spacer()
                        Button("Select Video") {
                            showFilePicker = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.primary)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .pipelineCard(padding: 14)

                    // Cut Seconds Controls
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Skip Intro / Cut Start Seconds")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.textPrimary)

                        HStack(spacing: 10) {
                            TextField("5.0", text: $cutSecondsText)
                                .keyboardType(.decimalPad)
                                .padding(12)
                                .background(AppTheme.surfaceCardElevated)
                                .foregroundColor(AppTheme.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(AppTheme.surfaceCardBorder, lineWidth: 1)
                                )

                            Button("Current Pos") {
                                if let p = player {
                                    let sec = CMTimeGetSeconds(p.currentTime())
                                    if sec.isFinite && sec >= 0 {
                                        cutSecondsText = String(format: "%.1f", sec)
                                    }
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(AppTheme.cyan.opacity(0.2))
                            .foregroundColor(AppTheme.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        HStack(spacing: 8) {
                            quickCutButton("5.0s") { cutSecondsText = "5.0" }
                            quickCutButton("10.0s") { cutSecondsText = "10.0" }
                            quickCutButton("15.0s") { cutSecondsText = "15.0" }
                            quickCutButton("30.0s") { cutSecondsText = "30.0" }
                        }

                        Divider().background(AppTheme.surfaceCardBorder).padding(.vertical, 4)

                        // AI Vision Ad Detection (Gemini / DeepSeek)
                        HStack {
                            Label("AI Auto-Detect Intro Ad", systemImage: "sparkles")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppTheme.primaryLight)
                            Spacer()
                            Picker("AI", selection: $aiProvider) {
                                ForEach(AIProvider.allCases) { p in
                                    Text(p.rawValue).tag(p)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 170)
                        }

                        Button {
                            runAIAdDetection()
                        } label: {
                            if isScanningAI {
                                HStack(spacing: 8) {
                                    ProgressView().tint(.white)
                                    Text("Scanning frames with \(aiProvider.rawValue)...")
                                }
                            } else {
                                Label("Scan Intro with \(aiProvider.rawValue) Vision AI", systemImage: "wand.and.stars")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(color: AppTheme.primary))
                        .disabled(selectedVideoURL == nil || isScanningAI || isTrimming)

                        if (aiProvider == .gemini && !api.hasGeminiKey) || (aiProvider == .deepseek && !api.hasDeepSeekKey) {
                            NavigationLink(destination: ApiSetupView()) {
                                Text("Configure \(aiProvider.rawValue) API Key in API Setup →")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(AppTheme.amber)
                            }
                        }
                    }
                    .pipelineCard()

                    if isTrimming {
                        VStack(spacing: 6) {
                            ProgressView(value: trimProgress)
                                .tint(AppTheme.emerald)
                            Text("Lossless stream copy: \(Int(trimProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .pipelineCard(padding: 12)
                    }

                    if let status = statusMessage {
                        Text(status)
                            .font(.footnote)
                            .foregroundColor(AppTheme.emerald)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pipelineCard(cornerRadius: 12, padding: 12)
                    }

                    // Execute Lossless Trim
                    Button {
                        startLosslessTrim()
                    } label: {
                        Label("Trim Intro Losslessly (Zero Quality Loss)", systemImage: "bolt.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: AppTheme.emerald))
                    .disabled(selectedVideoURL == nil || isTrimming)

                    // Export Actions if output ready
                    if let outURL = outputFileURL {
                        HStack(spacing: 10) {
                            ShareLink(item: outURL) {
                                Label("Share / Save", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(AppTheme.surfaceCardElevated)
                                    .foregroundColor(AppTheme.textPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Button {
                                saveToPhotoLibrary(url: outURL)
                            } label: {
                                Label("Save to Photos", systemImage: "photo.on.rectangle")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(AppTheme.primary.opacity(0.2))
                                    .foregroundColor(AppTheme.primaryLight)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }

                    if let photoMsg = savedToPhotosMessage {
                        Text(photoMsg)
                            .font(.caption)
                            .foregroundColor(AppTheme.cyan)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Lossless Intro Trimmer")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            player?.pause()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importVideo(url)
                }
            case .failure(let error):
                statusMessage = "Selection error: \(error.localizedDescription)"
            }
        }
    }

    private func quickCutButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(AppTheme.surfaceCardElevated)
            .foregroundColor(AppTheme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.surfaceCardBorder, lineWidth: 1)
            )
    }

    private func importVideo(_ url: URL) {
        statusMessage = nil
        outputFileURL = nil
        savedToPhotosMessage = nil

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        // Copy into temp sandbox so AVPlayer & AVAssetExportSession always have stable read access
        let tempDir = FileManager.default.temporaryDirectory
        let localCopy = tempDir.appendingPathComponent("input_\(UUID().uuidString)_\(url.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: url, to: localCopy)
            selectedVideoURL = localCopy
            selectedVideoName = url.lastPathComponent
            let newPlayer = AVPlayer(url: localCopy)
            player = newPlayer

            Task {
                let asset = AVURLAsset(url: localCopy)
                if let dur = try? await asset.load(.duration) {
                    let total = Int(CMTimeGetSeconds(dur))
                    await MainActor.run {
                        durationText = String(format: "Duration: %02d:%02d", total / 60, total % 60)
                    }
                }
            }
        } catch {
            statusMessage = "Failed to open video: \(error.localizedDescription)"
        }
    }

    private func runAIAdDetection() {
        guard let inputURL = selectedVideoURL else { return }
        let key = aiProvider == .gemini ? api.geminiApiKey : api.deepseekApiKey
        let model = aiProvider == .gemini ? api.geminiModel : api.deepseekModel
        let endpoint = api.deepseekEndpoint

        isScanningAI = true
        statusMessage = nil

        Task {
            do {
                let res = try await AIAdDetectorService.detectIntroAd(
                    videoURL: inputURL,
                    provider: aiProvider,
                    apiKey: key,
                    modelName: model,
                    deepseekEndpoint: endpoint
                )
                isScanningAI = false
                if res.adDetected && res.cutSeconds > 0 {
                    cutSecondsText = String(format: "%.1f", res.cutSeconds)
                    statusMessage = "AI detected \(res.adType) ending at \(String(format: "%.1f", res.cutSeconds))s — \(res.reason)"
                    let seekTime = CMTime(seconds: res.cutSeconds, preferredTimescale: 600)
                    _ = await player?.seek(to: seekTime)
                } else {
                    statusMessage = "AI Scan: \(res.reason)"
                }
            } catch {
                isScanningAI = false
                statusMessage = "AI Scan Error: \(error.localizedDescription)"
            }
        }
    }

    private func startLosslessTrim() {
        guard let inputURL = selectedVideoURL else { return }
        guard let cutSec = Double(cutSecondsText.trimmingCharacters(in: .whitespaces)), cutSec > 0 else {
            statusMessage = "Please enter cut seconds greater than 0."
            return
        }

        isTrimming = true
        trimProgress = 0
        statusMessage = nil
        savedToPhotosMessage = nil
        player?.pause()

        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let trimmedDir = docsDir.appendingPathComponent("Trimmed", isDirectory: true)
        try? FileManager.default.createDirectory(at: trimmedDir, withIntermediateDirectories: true)

        let base = (selectedVideoName as NSString).deletingPathExtension
        let outURL = trimmedDir.appendingPathComponent("Trimmed_\(Int(Date().timeIntervalSince1970))_\(base).mp4")

        Task {
            do {
                let finalURL = try await VideoTrimmerEngine.trimLossless(
                    inputURL: inputURL,
                    outputURL: outURL,
                    startSeconds: cutSec
                ) { progress in
                    Task { @MainActor in
                        trimProgress = progress
                    }
                }

                isTrimming = false
                outputFileURL = finalURL
                statusMessage = "Trimmed losslessly! Saved to Files -> Video Pipeline -> Trimmed/\(finalURL.lastPathComponent)"
                player = AVPlayer(url: finalURL)
                player?.play()
            } catch {
                isTrimming = false
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func saveToPhotoLibrary(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    savedToPhotosMessage = "Photos permission denied. File is still saved in iOS Files app."
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                Task { @MainActor in
                    if success {
                        savedToPhotosMessage = "Saved to iPhone Photos library!"
                    } else {
                        savedToPhotosMessage = "Photos save error: \(error?.localizedDescription ?? "Unknown")"
                    }
                }
            }
        }
    }
}
