import SwiftUI
import Photos
import UniformTypeIdentifiers
import UIKit

struct UploaderStudioView: View {
    private enum UploadTab: String, CaseIterable, Identifiable {
        case telegram = "Telegram MTProto"
        case tiktok = "TikTok"
        case queue = "Queue"
        var id: String { rawValue }
    }

    @ObservedObject private var mtproto = TelegramMTProtoManager.shared

    @State private var activeTab: UploadTab = .telegram
    @State private var selectedVideo: VideoAssetMetadata? = nil
    @State private var showFileImporter: Bool = false
    @State private var showAppLibrarySheet: Bool = false
    @State private var localLibraryVideos: [URL] = []

    // MTProto destination
    @State private var selectedChat: MTProtoChatItem? = nil
    @State private var customUsername: String = ""
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
                                    .fill(mtproto.isAuthorized ? AppTheme.emerald : AppTheme.amber)
                                    .frame(width: 7, height: 7)
                                Text(mtproto.isAuthorized
                                     ? "MTProto: \(mtproto.connectedUserName) (Up to 2 GB)"
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
            if mtproto.isAuthorized && mtproto.chats.isEmpty {
                mtproto.loadUserChats()
            }
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
                    Button("Clear") { selectedVideo = nil }
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

    // MARK: - Tab 1: Telegram MTProto Uploader (Up to 2 GB)
    private var telegramUploadPanel: some View {
        VStack(spacing: 16) {
            if !mtproto.isAuthorized {
                VStack(spacing: 12) {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.system(size: 42))
                        .foregroundColor(AppTheme.cyan)
                    Text("Sign In with Telegram MTProto")
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Log in with your personal phone number & OTP to upload large videos (up to 2 GB) directly to any Telegram channel or group where you are an admin.")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    NavigationLink(destination: ApiSetupView()) {
                        Label("Login Telegram (Phone + OTP)", systemImage: "person.badge.key.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppTheme.cyan)
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .pipelineCard()
            } else {
                // Target Channel Selector Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Destination Channel / Group", systemImage: "megaphone.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(AppTheme.cyan)
                        Spacer()
                        Button {
                            mtproto.loadUserChats()
                        } label: {
                            if mtproto.isLoadingChats {
                                ProgressView().scaleEffect(0.75)
                            } else {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(AppTheme.cyan)
                            }
                        }
                    }

                    if !mtproto.chats.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(mtproto.chats) { chat in
                                    Button {
                                        selectedChat = chat
                                        customUsername = ""
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: chat.isChannel ? "megaphone.fill" : "person.2.fill")
                                                .font(.caption2)
                                            Text(chat.title)
                                                .font(.caption2.weight(.semibold))
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 7)
                                        .background(selectedChat?.id == chat.id ? AppTheme.cyan : AppTheme.surfaceCardElevated)
                                        .foregroundColor(selectedChat?.id == chat.id ? .black : AppTheme.textPrimary)
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    TextField("Or enter public @channel_username", text: $customUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: customUsername) { newVal in
                            if !newVal.isEmpty { selectedChat = nil }
                        }
                        .padding(12)
                        .background(AppTheme.surfaceCardElevated)
                        .foregroundColor(AppTheme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.surfaceCardBorder, lineWidth: 1))
                }
                .pipelineCard()

                // Caption & Options Card
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

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            formatChip("Episode") {
                                let name = selectedVideo.map { ($0.fileName as NSString).deletingPathExtension } ?? "Series Ep - 01"
                                captionText = "🎬 \(name)\n\n📥 Quality: HD\n🔔 Join Channel for more episodes!"
                            }
                            formatChip("Movie") {
                                let name = selectedVideo.map { ($0.fileName as NSString).deletingPathExtension } ?? "Movie Title"
                                captionText = "🍿 \(name)\n⭐ Full HD Streaming"
                            }
                            formatChip("Clear") { captionText = "" }
                        }
                    }

                    TextEditor(text: $captionText)
                        .frame(minHeight: 85)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(AppTheme.surfaceCardElevated)
                        .foregroundColor(AppTheme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.surfaceCardBorder, lineWidth: 1))

                    Toggle(isOn: $protectContent) {
                        Text("Protect Content (Disable Save / Forward)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppTheme.textPrimary)
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

                // Live MTProto Upload Progress
                if mtproto.isUploading {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Uploading via Telegram MTProto...")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(AppTheme.cyan)
                            Spacer()
                            Text(mtproto.uploadSpeedText)
                                .font(.caption.monospacedDigit().bold())
                                .foregroundColor(AppTheme.emerald)
                        }
                        ProgressView(value: mtproto.uploadProgress)
                            .tint(AppTheme.cyan)
                        Text(mtproto.uploadStatusText)
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .pipelineCard()
                }

                if let err = mtproto.uploadError {
                    feedbackBanner(text: err, isError: true)
                }
                if let ok = mtproto.uploadSuccess {
                    feedbackBanner(text: ok, isError: false)
                }

                Button {
                    guard let vid = selectedVideo else { return }
                    let title = selectedChat?.title ?? (customUsername.isEmpty ? "Telegram" : customUsername)
                    mtproto.uploadVideo(
                        chatId: selectedChat?.id,
                        publicUsername: selectedChat == nil ? customUsername : nil,
                        targetTitle: title,
                        videoURL: vid.url,
                        caption: captionText,
                        durationSeconds: Int(vid.durationSeconds),
                        width: vid.width,
                        height: vid.height,
                        protectContent: protectContent,
                        disableNotification: disableNotification
                    )
                } label: {
                    Label("Publish Video via MTProto", systemImage: "paperplane.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: AppTheme.emerald))
                .disabled(selectedVideo == nil || (selectedChat == nil && customUsername.trimmingCharacters(in: .whitespaces).isEmpty) || mtproto.isUploading)
            }
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

    // MARK: - Tab 3: Upload History
    private var uploadQueuePanel: some View {
        VStack(spacing: 12) {
            if mtproto.uploadHistory.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.textMuted)
                    Text("No Uploads Yet")
                        .font(.headline)
                        .foregroundColor(AppTheme.textSecondary)
                    Text("Your MTProto published Telegram videos and upload status logs will appear here.")
                        .font(.caption)
                        .foregroundColor(AppTheme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .pipelineCard()
            } else {
                ForEach(mtproto.uploadHistory) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundColor(item.isCompleted ? AppTheme.emerald : AppTheme.danger)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.fileName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(AppTheme.textPrimary)
                                .lineLimit(1)
                            Text("Target: \(item.targetTitle) • \(item.status)")
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

    // MARK: - App Library Sheet
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
            let meta = await VideoInspector.inspectVideo(url: targetURL)
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
