import SwiftUI
import Photos
import UniformTypeIdentifiers
import UIKit

struct UploaderStudioView: View {
    private enum UploadTab: String, CaseIterable, Identifiable {
        case telegram = "Telegram"
        case tiktok = "TikTok"
        case queue = "Queue"
        var id: String { rawValue }
    }

    @ObservedObject private var api = ApiSettingsStore.shared
    @StateObject private var uploader = TelegramUploadManager()

    @State private var activeTab: UploadTab = .telegram
    @State private var selectedVideo: VideoAssetMetadata? = nil
    @State private var showFileImporter: Bool = false
    @State private var showAppLibrarySheet: Bool = false
    @State private var localLibraryVideos: [URL] = []

    // Telegram options
    @State private var targetChatId: String = UserDefaults.standard.string(forKey: "vp_last_tg_chat") ?? ""
    @State private var discoveredChats: [DiscoveredTelegramChat] = []
    @State private var isDiscoveringChats: Bool = false
    @State private var captionText: String = ""
    @State private var protectContent: Bool = true
    @State private var disableNotification: Bool = false

    // TikTok options
    @State private var tiktokCaption: String = ""
    @State private var tiktokNotice: String? = nil

    private let quickHashtags = ["#fyp", "#myanmar", "#movieclips", "#dramaclip", "#anime", "#viral", "#series"]

    var body: some View {
        ZStack {
            AppTheme.bgDark.ignoresSafeArea()

            VStack(spacing: 0) {
                // Studio Header Bar
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(colors: [AppTheme.primary, AppTheme.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 44, height: 44)
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Uploader Studio")
                                .font(.headline)
                                .foregroundColor(AppTheme.textPrimary)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(api.hasTelegramBot ? AppTheme.emerald : AppTheme.amber)
                                    .frame(width: 7, height: 7)
                                Text(api.hasTelegramBot ? "Telegram Bot Connected" : "Connect Bot for Telegram Upload")
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

                    // Mode Switcher
                    Picker("Upload Mode", selection: $activeTab) {
                        ForEach(UploadTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.surfaceCard)
                .overlay(
                    Rectangle()
                        .fill(AppTheme.surfaceCardBorder)
                        .frame(height: 1),
                    alignment: .bottom
                )

                ScrollView {
                    VStack(spacing: 16) {
                        if activeTab != .queue {
                            videoSelectionCard
                        }

                        switch activeTab {
                        case .telegram:
                            telegramUploadPanel
                        case .tiktok:
                            tiktokStudioPanel
                        case .queue:
                            uploadQueuePanel
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Uploader Studio")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshLocalLibrary()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                loadPickedVideo(url: url, securityScoped: true)
            }
        }
        .sheet(isPresented: $showAppLibrarySheet) {
            appLibraryPickerSheet
        }
    }

    // MARK: - Shared Video Selection & Preview Card
    private var videoSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Selected Media", systemImage: "film.stack.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                if selectedVideo != nil {
                    Button("Clear") {
                        selectedVideo = nil
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.danger)
                }
            }

            if let vid = selectedVideo {
                HStack(spacing: 12) {
                    if let img = vid.thumbnail {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 92, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.surfaceCardBorder, lineWidth: 1))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppTheme.surfaceCardElevated)
                                .frame(width: 92, height: 64)
                            Image(systemName: "film")
                                .foregroundColor(AppTheme.primaryLight)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(vid.fileName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            metaBadge(String(format: "%.1f MB", Double(vid.fileSizeBytes) / (1024 * 1024)), color: AppTheme.cyan)
                            metaBadge(formatDuration(vid.durationSeconds), color: AppTheme.emerald)
                            metaBadge(vid.resolutionText, color: AppTheme.primaryLight)
                        }
                    }
                    Spacer()
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(AppTheme.primaryLight)
                    Text("Pick a video from iOS Files or App Downloads / Trimmed")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.surfaceCardElevated.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 10) {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Browse Files", systemImage: "folder.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.primary.opacity(0.18))
                        .foregroundColor(AppTheme.primaryLight)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    refreshLocalLibrary()
                    showAppLibrarySheet = true
                } label: {
                    Label("App Library (\(localLibraryVideos.count))", systemImage: "tray.full.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.emerald.opacity(0.18))
                        .foregroundColor(AppTheme.emerald)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .pipelineCard()
    }

    // MARK: - Tab 1: Telegram Channel / Group Uploader
    private var telegramUploadPanel: some View {
        VStack(spacing: 16) {
            // Destination Channel Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Target Channel / Group", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(AppTheme.cyan)
                    Spacer()
                    if api.hasTelegramBot {
                        Button {
                            discoverRecentChats()
                        } label: {
                            if isDiscoveringChats {
                                ProgressView().scaleEffect(0.75)
                            } else {
                                Label("Detect Chats", systemImage: "antenna.radiowaves.left.and.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(AppTheme.cyan)
                            }
                        }
                    }
                }

                TextField("@channel_username or -1001234567890", text: $targetChatId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(AppTheme.surfaceCardElevated)
                    .foregroundColor(AppTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.surfaceCardBorder, lineWidth: 1))

                if !discoveredChats.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(discoveredChats) { chat in
                                Button {
                                    targetChatId = chat.id
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: chat.type == "channel" ? "megaphone.fill" : "person.2.fill")
                                            .font(.caption2)
                                        Text(chat.title)
                                            .font(.caption2.weight(.semibold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(targetChatId == chat.id ? AppTheme.cyan : AppTheme.surfaceCardElevated)
                                    .foregroundColor(targetChatId == chat.id ? .black : AppTheme.textPrimary)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
            .pipelineCard()

            // Caption & Publishing Options Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Caption & Templates", systemImage: "text.alignleft")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(AppTheme.primaryLight)
                    Spacer()
                    if let vid = selectedVideo {
                        Button("Use Filename") {
                            captionText = (vid.fileName as NSString).deletingPathExtension
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(AppTheme.emerald)
                    }
                }

                // Quick HTML formatting pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        formatChip("Bold") { captionText += "<b>Title</b>" }
                        formatChip("Italic") { captionText += "<i>Subtitle</i>" }
                        formatChip("Episode") {
                            let name = selectedVideo.map { ($0.fileName as NSString).deletingPathExtension } ?? "Series Ep - 01"
                            captionText = "🎬 <b>\(name)</b>\n\n📥 Quality: HD\n🔔 Join Channel for more episodes!"
                        }
                        formatChip("Clear") { captionText = "" }
                    }
                }

                TextEditor(text: $captionText)
                    .frame(minHeight: 88)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(AppTheme.surfaceCardElevated)
                    .foregroundColor(AppTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.surfaceCardBorder, lineWidth: 1))

                Toggle(isOn: $protectContent) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Protect Content (Disable Save / Forward)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("Prevents channel members from forwarding or saving")
                            .font(.caption2)
                            .foregroundColor(AppTheme.textMuted)
                    }
                }
                .tint(AppTheme.emerald)

                Toggle(isOn: $disableNotification) {
                    Text("Silent Broadcast (No Notification Sound)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                .tint(AppTheme.primary)
            }
            .pipelineCard()

            // Live Upload Progress Card
            if uploader.isUploading {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Uploading to Telegram...")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(AppTheme.cyan)
                        Spacer()
                        Text(uploader.speedText)
                            .font(.caption.monospacedDigit().bold())
                            .foregroundColor(AppTheme.emerald)
                    }
                    ProgressView(value: uploader.progress)
                        .tint(AppTheme.cyan)
                    HStack {
                        Text(uploader.statusText)
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Button("Cancel") {
                            uploader.cancelUpload()
                        }
                        .font(.caption.bold())
                        .foregroundColor(AppTheme.danger)
                    }
                }
                .pipelineCard()
            }

            if let err = uploader.errorMessage {
                feedbackBanner(text: err, isError: true)
            }
            if let ok = uploader.successMessage {
                feedbackBanner(text: ok, isError: false)
            }

            // Primary Publish Button
            Button {
                guard let vid = selectedVideo else { return }
                UserDefaults.standard.set(targetChatId, forKey: "vp_last_tg_chat")
                uploader.uploadVideo(
                    botToken: api.telegramBotToken,
                    chatId: targetChatId,
                    videoURL: vid.url,
                    caption: captionText,
                    protectContent: protectContent,
                    disableNotification: disableNotification
                )
            } label: {
                Label("Publish Video to Telegram", systemImage: "paperplane.fill")
            }
            .buttonStyle(PrimaryButtonStyle(color: AppTheme.emerald))
            .disabled(selectedVideo == nil || uploader.isUploading)
        }
    }

    // MARK: - Tab 2: TikTok Studio Panel
    private var tiktokStudioPanel: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label("TikTok Caption & Hashtags", systemImage: "music.note")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(AppTheme.primaryLight)

                TextEditor(text: $tiktokCaption)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(AppTheme.surfaceCardElevated)
                    .foregroundColor(AppTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.surfaceCardBorder, lineWidth: 1))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(quickHashtags, id: \.self) { tag in
                            formatChip(tag) {
                                if !tiktokCaption.contains(tag) {
                                    tiktokCaption = tiktokCaption.isEmpty ? tag : "\(tiktokCaption) \(tag)"
                                }
                            }
                        }
                    }
                }

                Button {
                    UIPasteboard.general.string = tiktokCaption
                    tiktokNotice = "Caption copied to clipboard — paste right inside TikTok!"
                } label: {
                    Label("Copy Caption for TikTok", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.surfaceCardElevated)
                        .foregroundColor(AppTheme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .pipelineCard()

            if let note = tiktokNotice {
                feedbackBanner(text: note, isError: false)
            }

            if let vid = selectedVideo {
                VStack(spacing: 10) {
                    ShareLink(item: vid.url) {
                        Label("Share Directly to TikTok App", systemImage: "square.and.arrow.up.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LinearGradient(colors: [Color(hex: 0xFE2C55), Color(hex: 0x25F4EE)], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        saveToPhotos(url: vid.url)
                    } label: {
                        Label("Save Video to iPhone Photos", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: AppTheme.primary))
                }
            }
        }
    }

    // MARK: - Tab 3: Upload Queue & History
    private var uploadQueuePanel: some View {
        VStack(spacing: 12) {
            if uploader.queueHistory.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.textMuted)
                    Text("No Uploads Yet")
                        .font(.headline)
                        .foregroundColor(AppTheme.textSecondary)
                    Text("Your published Telegram videos and upload status logs will appear here.")
                        .font(.caption)
                        .foregroundColor(AppTheme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .pipelineCard()
            } else {
                ForEach(uploader.queueHistory) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundColor(item.isCompleted ? AppTheme.emerald : AppTheme.danger)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.fileName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(AppTheme.textPrimary)
                                .lineLimit(1)
                            Text("Target: \(item.targetChat) • \(item.status)")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .pipelineCard(cornerRadius: 12, padding: 12)
                }
            }
        }
    }

    // MARK: - App Library Picker Sheet
    private var appLibraryPickerSheet: some View {
        NavigationStack {
            ZStack {
                AppTheme.bgDark.ignoresSafeArea()
                if localLibraryVideos.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 38))
                            .foregroundColor(AppTheme.textMuted)
                        Text("No Downloaded or Trimmed Videos Yet")
                            .font(.headline)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                } else {
                    List(localLibraryVideos, id: \.self) { fileURL in
                        Button {
                            loadPickedVideo(url: fileURL, securityScoped: false)
                            showAppLibrarySheet = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "film.fill")
                                    .foregroundColor(AppTheme.emerald)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fileURL.lastPathComponent)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(AppTheme.textPrimary)
                                        .lineLimit(1)
                                    Text(fileURL.deletingLastPathComponent().lastPathComponent)
                                        .font(.caption2)
                                        .foregroundColor(AppTheme.textMuted)
                                }
                                Spacer()
                            }
                        }
                        .listRowBackground(AppTheme.surfaceCard)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("App Video Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showAppLibrarySheet = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Helpers
    private func metaBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.16))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func formatChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.surfaceCardElevated)
            .foregroundColor(AppTheme.textPrimary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AppTheme.surfaceCardBorder, lineWidth: 1))
    }

    private func feedbackBanner(text: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            Text(text).font(.caption)
        }
        .foregroundColor(isError ? AppTheme.danger : AppTheme.emerald)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background((isError ? AppTheme.danger : AppTheme.emerald).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatDuration(_ sec: Double) -> String {
        let total = max(0, Int(sec))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func loadPickedVideo(url: URL, securityScoped: Bool) {
        let accessed = securityScoped ? url.startAccessingSecurityScopedResource() : false
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let targetURL: URL
        if securityScoped {
            let tempCopy = FileManager.default.temporaryDirectory.appendingPathComponent("upload_src_\(UUID().uuidString)_\(url.lastPathComponent)")
            if (try? FileManager.default.copyItem(at: url, to: tempCopy)) != nil {
                targetURL = tempCopy
            } else {
                targetURL = url
            }
        } else {
            targetURL = url
        }

        Task {
            let meta = await TelegramUploadManager.inspectVideo(url: targetURL)
            selectedVideo = meta
        }
    }

    private func refreshLocalLibrary() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folders = [
            docs.appendingPathComponent("Downloads", isDirectory: true),
            docs.appendingPathComponent("Trimmed", isDirectory: true)
        ]
        var found: [URL] = []
        let exts: Set<String> = ["mp4", "mov", "m4v", "mkv"]
        for dir in folders {
            if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) {
                for f in files where exts.contains(f.pathExtension.lowercased()) {
                    found.append(f)
                }
            }
        }
        localLibraryVideos = found.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func discoverRecentChats() {
        isDiscoveringChats = true
        Task {
            discoveredChats = await TelegramUploadManager.discoverChats(botToken: api.telegramBotToken)
            isDiscoveringChats = false
        }
    }

    private func saveToPhotos(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in tiktokNotice = "Photos access denied." }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { ok, err in
                Task { @MainActor in
                    tiktokNotice = ok ? "Saved to iPhone Photos — ready for TikTok!" : (err?.localizedDescription ?? "Save failed")
                }
            }
        }
    }
}
