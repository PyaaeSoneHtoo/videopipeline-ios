import Foundation
import TDLibKit
import UIKit

enum MTProtoAuthStage: Equatable {
    case disconnected
    case connecting
    case waitPhoneNumber
    case waitCode
    case waitPassword(hint: String)
    case ready
}

struct MTProtoChatItem: Identifiable, Hashable {
    let id: Int64
    let title: String
    let isChannel: Bool
    let isProtected: Bool
}

struct MTProtoVideoMessage: Identifiable, Hashable {
    let id: Int64
    let chatId: Int64
    let fileId: Int
    let fileName: String
    let caption: String
    let sizeBytes: Int64
    let durationSeconds: Int
    let isProtected: Bool
}

struct MTProtoUploadLogItem: Identifiable {
    let id = UUID()
    let fileName: String
    let targetTitle: String
    var status: String
    var isCompleted: Bool
    var isFailed: Bool
}

@MainActor
final class TelegramMTProtoManager: ObservableObject {
    static let shared = TelegramMTProtoManager()

    // Auth state
    @Published var authStage: MTProtoAuthStage = .disconnected
    @Published var authMessage: String? = nil
    @Published var authError: String? = nil
    @Published var isBusyAuth: Bool = false
    @Published var connectedUserName: String = ""
    @Published var connectedPhone: String = ""

    // Chats & Messages
    @Published var chats: [MTProtoChatItem] = []
    @Published var isLoadingChats: Bool = false
    @Published var channelVideos: [MTProtoVideoMessage] = []
    @Published var isLoadingMessages: Bool = false

    // Active MTProto Download
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0
    @Published var downloadFileName: String = ""
    @Published var downloadDetailText: String = ""
    @Published var downloadSpeedText: String = ""
    @Published var lastDownloadedURL: URL? = nil
    @Published var downloadError: String? = nil

    // Active MTProto Upload
    @Published var isUploading: Bool = false
    @Published var uploadProgress: Double = 0
    @Published var uploadStatusText: String = ""
    @Published var uploadSpeedText: String = ""
    @Published var uploadError: String? = nil
    @Published var uploadSuccess: String? = nil
    @Published var uploadHistory: [MTProtoUploadLogItem] = []

    var isAuthorized: Bool { authStage == .ready }

    private let clientManager = TDLibClientManager()
    private var client: TDLibClient?
    private var currentApiId: Int = 0
    private var currentApiHash: String = ""
    private var pendingPhoneNumberToSend: String? = nil
    private var isSendingParameters: Bool = false

    private var activeDownloadFileId: Int? = nil
    private var activeDownloadTargetName: String = ""
    private var downloadStartTime: Foundation.Date = Foundation.Date()

    private var activeUploadFileId: Int? = nil
    private var activeUploadMessageId: Int64? = nil
    private var activeUploadFileName: String = ""
    private var activeUploadTargetTitle: String = ""
    private var uploadStartTime: Foundation.Date = Foundation.Date()

    private init() {
        // Auto-reconnect silently if API ID & Hash were saved previously
        let api = ApiSettingsStore.shared
        if api.hasTelegramMTProtoKeys {
            startClient(apiIdString: api.telegramApiId, apiHash: api.telegramApiHash)
        }
    }

    // MARK: - Start & Connect MTProto Client (Silent Auto-Reconnect)
    func startClient(apiIdString: String, apiHash: String) {
        let cleanIdStr = apiIdString.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedId = Int(cleanIdStr), parsedId > 0, !cleanHash.isEmpty else {
            authError = "Please enter a valid numeric API ID and API Hash from my.telegram.org."
            isBusyAuth = false
            return
        }

        let credentialsChanged = (currentApiId != 0 && (currentApiId != parsedId || currentApiHash != cleanHash))
        currentApiId = parsedId
        currentApiHash = cleanHash
        authError = nil
        authMessage = "Connecting to Telegram MTProto..."

        if let existing = client, !credentialsChanged {
            if authStage == .disconnected {
                authStage = .connecting
            }
            Task {
                if let state = try? await existing.getAuthorizationState() {
                    self.handleAuthState(state)
                }
            }
            return
        }

        if let oldClient = client {
            client = nil
            isSendingParameters = false
            Task { _ = try? await oldClient.close() }
        }

        authStage = .connecting
        isSendingParameters = false
        let td = clientManager.createClient { [weak self] data, tdClient in
            guard let self = self else { return }
            if let update = try? tdClient.decoder.decode(Update.self, from: data) {
                Task { @MainActor in
                    self.handleUpdate(update)
                }
            }
        }
        self.client = td

        Task {
            if let state = try? await td.getAuthorizationState() {
                self.handleAuthState(state)
            }
        }
    }

    // MARK: - All-in-One: Connect MTProto & Send OTP Code in 1 Tap
    func connectAndSendPhone(phone: String, apiIdString: String, apiHash: String) {
        let cleanPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanIdStr = apiIdString.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanPhone.isEmpty else {
            authError = "Enter your Telegram mobile number with country code (e.g. +959... or +1...)."
            return
        }
        guard let parsedId = Int(cleanIdStr), parsedId > 0, !cleanHash.isEmpty else {
            authError = "Enter your numeric Telegram API ID and API Hash from my.telegram.org."
            return
        }

        ApiSettingsStore.shared.telegramPhone = cleanPhone
        ApiSettingsStore.shared.telegramApiId = cleanIdStr
        ApiSettingsStore.shared.telegramApiHash = cleanHash

        authError = nil
        isBusyAuth = true

        let credentialsChanged = (currentApiId != 0 && (currentApiId != parsedId || currentApiHash != cleanHash))

        // If already waiting for phone number with the same API credentials, submit immediately
        if client != nil, !credentialsChanged, authStage == .waitPhoneNumber {
            submitPhoneNumber(cleanPhone)
            return
        }

        // Queue phone number and spin up / reconnect TDLib client
        pendingPhoneNumberToSend = cleanPhone
        startClient(apiIdString: cleanIdStr, apiHash: cleanHash)
    }

    func resetAuthFlow() {
        pendingPhoneNumberToSend = nil
        isBusyAuth = false
        authError = nil
        authMessage = nil
        if let oldClient = client {
            client = nil
            isSendingParameters = false
            Task { _ = try? await oldClient.close() }
        }
        authStage = .disconnected
    }

    // MARK: - Auth Actions
    func submitPhoneNumber(_ phone: String) {
        let cleaned = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            authError = "Enter your phone number with country code (e.g. +959...)."
            isBusyAuth = false
            return
        }
        guard let td = client else {
            authError = "Telegram client not connected yet."
            isBusyAuth = false
            return
        }
        authError = nil
        isBusyAuth = true
        authMessage = "Sending OTP code to \(cleaned)..."
        ApiSettingsStore.shared.telegramPhone = cleaned

        Task {
            do {
                _ = try await td.setAuthenticationPhoneNumber(phoneNumber: cleaned, settings: nil)
            } catch {
                self.isBusyAuth = false
                self.authError = "Phone error: \(error.localizedDescription)"
            }
        }
    }

    func submitAuthCode(_ code: String) {
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            authError = "Enter the 5-digit OTP code from Telegram."
            return
        }
        guard let td = client else { return }
        authError = nil
        isBusyAuth = true
        authMessage = "Verifying OTP code..."

        Task {
            do {
                _ = try await td.checkAuthenticationCode(code: cleaned)
            } catch {
                self.isBusyAuth = false
                self.authError = "OTP error: \(error.localizedDescription)"
            }
        }
    }

    func submitTwoFactorPassword(_ password: String) {
        guard !password.isEmpty else {
            authError = "Enter your 2FA Cloud Password."
            return
        }
        guard let td = client else { return }
        authError = nil
        isBusyAuth = true
        authMessage = "Verifying 2FA password..."

        Task {
            do {
                _ = try await td.checkAuthenticationPassword(password: password)
            } catch {
                self.isBusyAuth = false
                self.authError = "2FA error: \(error.localizedDescription)"
            }
        }
    }

    func logout() {
        pendingPhoneNumberToSend = nil
        isBusyAuth = false
        guard let td = client else {
            authStage = .disconnected
            return
        }
        authMessage = "Logging out..."
        Task {
            _ = try? await td.logOut()
            self.connectedUserName = ""
            self.connectedPhone = ""
            self.chats = []
            self.channelVideos = []
            self.authStage = .disconnected
            self.authMessage = "Logged out from Telegram."
        }
    }

    // MARK: - Chats & Video History
    func loadUserChats() {
        guard let td = client, isAuthorized else { return }
        isLoadingChats = true
        Task {
            do {
                _ = try? await td.loadChats(chatList: .chatListMain, limit: 100)
                let chatList = try await td.getChats(chatList: .chatListMain, limit: 100)
                var loaded: [MTProtoChatItem] = []
                for cid in chatList.chatIds {
                    if let chat = try? await td.getChat(chatId: cid) {
                        var isChannel = false
                        if case .chatTypeSupergroup(let sg) = chat.type {
                            isChannel = sg.isChannel
                        }
                        loaded.append(MTProtoChatItem(
                            id: chat.id,
                            title: chat.title,
                            isChannel: isChannel,
                            isProtected: chat.hasProtectedContent
                        ))
                    }
                }
                self.chats = loaded
            } catch {
                self.downloadError = "Could not load chats: \(error.localizedDescription)"
            }
            self.isLoadingChats = false
        }
    }

    func loadVideosForChat(_ chat: MTProtoChatItem) {
        guard let td = client, isAuthorized else { return }
        isLoadingMessages = true
        channelVideos = []

        Task {
            var collected: [MTProtoVideoMessage] = []
            var fromMessageId: Int64 = 0

            // Fetch up to 3 pages (~150 recent messages) to find videos
            for _ in 0..<3 {
                do {
                    let history = try await td.getChatHistory(
                        chatId: chat.id,
                        fromMessageId: fromMessageId,
                        limit: 50,
                        offset: 0,
                        onlyLocal: false
                    )
                    let msgs = history.messages ?? []
                    if msgs.isEmpty { break }

                    for msg in msgs {
                        if let vid = extractVideo(from: msg, defaultProtected: chat.isProtected) {
                            collected.append(vid)
                        }
                    }
                    fromMessageId = msgs.last?.id ?? 0
                    if fromMessageId == 0 || collected.count >= 40 { break }
                } catch {
                    break
                }
            }

            self.channelVideos = collected
            self.isLoadingMessages = false
        }
    }

    // MARK: - Download from Channel or t.me Post Link (Including Restricted Channels!)
    func downloadFromTelegramLink(_ link: String) {
        guard let td = client, isAuthorized else {
            downloadError = "Please log in to Telegram MTProto first."
            return
        }
        let cleanLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLink.isEmpty else { return }

        downloadError = nil
        downloadDetailText = "Resolving Telegram post link..."

        Task {
            do {
                let info = try await td.getMessageLinkInfo(url: cleanLink)
                guard let msg = info.message,
                      let vid = extractVideo(from: msg, defaultProtected: !msg.canBeSaved) else {
                    self.downloadError = "No video found at that Telegram link (make sure your account is a member of private channels)."
                    return
                }
                self.startVideoDownload(vid)
            } catch {
                self.downloadError = "Link error: \(error.localizedDescription)"
            }
        }
    }

    func startVideoDownload(_ item: MTProtoVideoMessage) {
        guard let td = client, isAuthorized else {
            downloadError = "Telegram MTProto is not connected."
            return
        }

        downloadError = nil
        lastDownloadedURL = nil
        isDownloading = true
        downloadProgress = 0
        downloadFileName = item.fileName
        downloadDetailText = "Starting MTProto download..."
        downloadSpeedText = ""
        activeDownloadFileId = item.fileId
        activeDownloadTargetName = item.fileName
        downloadStartTime = Foundation.Date()

        Task {
            do {
                let file = try await td.downloadFile(
                    fileId: item.fileId,
                    limit: 0,
                    offset: 0,
                    priority: 32,
                    synchronous: false
                )
                self.handleFileUpdate(file)
            } catch {
                self.isDownloading = false
                self.activeDownloadFileId = nil
                self.downloadError = "Download error: \(error.localizedDescription)"
            }
        }
    }

    func cancelActiveDownload() {
        guard let td = client, let fid = activeDownloadFileId else {
            isDownloading = false
            return
        }
        activeDownloadFileId = nil
        isDownloading = false
        downloadDetailText = "Cancelled"
        Task {
            _ = try? await td.cancelDownloadFile(fileId: fid, onlyIfPending: false)
        }
    }

    // MARK: - Upload Video via MTProto (Up to 2 GB!)
    func uploadVideo(
        chatId: Int64?,
        publicUsername: String?,
        targetTitle: String,
        videoURL: URL,
        caption: String,
        durationSeconds: Int,
        width: Int,
        height: Int,
        protectContent: Bool,
        disableNotification: Bool
    ) {
        guard let td = client, isAuthorized else {
            uploadError = "Please log in to Telegram MTProto first."
            return
        }

        isUploading = true
        uploadProgress = 0
        uploadStatusText = "Resolving target channel..."
        uploadSpeedText = ""
        uploadError = nil
        uploadSuccess = nil
        uploadStartTime = Foundation.Date()
        activeUploadFileName = videoURL.lastPathComponent
        activeUploadTargetTitle = targetTitle

        Task {
            do {
                let resolvedChatId: Int64
                if let cid = chatId {
                    resolvedChatId = cid
                } else if let uname = publicUsername?.trimmingCharacters(in: .whitespacesAndNewlines), !uname.isEmpty {
                    let cleanUname = uname.hasPrefix("@") ? String(uname.dropFirst()) : uname
                    let chat = try await td.searchPublicChat(username: cleanUname)
                    resolvedChatId = chat.id
                    self.activeUploadTargetTitle = chat.title
                } else {
                    self.isUploading = false
                    self.uploadError = "Select a Telegram channel/group or enter a @username."
                    return
                }

                self.uploadStatusText = "Uploading \(videoURL.lastPathComponent) via MTProto..."

                let inputVideo = InputVideo(
                    addedStickerFileIds: [],
                    cover: nil,
                    duration: max(1, durationSeconds),
                    height: max(0, height),
                    startTimestamp: 0,
                    supportsStreaming: true,
                    thumbnail: nil,
                    video: .inputFileLocal(InputFileLocal(path: videoURL.path)),
                    width: max(0, width)
                )

                let content = InputMessageContent.inputMessageVideo(
                    InputMessageVideo(
                        caption: FormattedText(entities: [], text: caption),
                        hasSpoiler: false,
                        selfDestructType: nil,
                        showCaptionAboveMedia: false,
                        video: inputVideo
                    )
                )

                let options = MessageSendOptions(
                    allowPaidBroadcast: false,
                    disableNotification: disableNotification,
                    effectId: TdInt64(0),
                    fromBackground: false,
                    onlyPreview: false,
                    paidMessageStarCount: 0,
                    protectContent: protectContent,
                    schedulingState: nil,
                    sendingId: 0,
                    suggestedPostInfo: nil,
                    updateOrderOfInstalledStickerSets: false
                )

                let sentMsg = try await td.sendMessage(
                    chatId: resolvedChatId,
                    inputMessageContent: content,
                    options: options,
                    replyMarkup: nil,
                    replyTo: nil,
                    topicId: nil
                )

                self.activeUploadMessageId = sentMsg.id
                if case .messageVideo(let mv) = sentMsg.content {
                    self.activeUploadFileId = mv.video.video.id
                }
            } catch {
                self.isUploading = false
                self.uploadError = "MTProto upload error: \(error.localizedDescription)"
                self.uploadHistory.insert(
                    MTProtoUploadLogItem(fileName: videoURL.lastPathComponent, targetTitle: targetTitle, status: "Error: \(error.localizedDescription)", isCompleted: false, isFailed: true),
                    at: 0
                )
            }
        }
    }

    // MARK: - TDLib Update Handler
    private func handleUpdate(_ update: Update) {
        switch update {
        case .updateAuthorizationState(let authUpdate):
            handleAuthState(authUpdate.authorizationState)
        case .updateFile(let fileUpdate):
            handleFileUpdate(fileUpdate.file)
        case .updateMessageSendSucceeded(let okUpd):
            if activeUploadMessageId == okUpd.oldMessageId || (isUploading && okUpd.message.isOutgoing) {
                isUploading = false
                uploadProgress = 1.0
                uploadStatusText = "100% Published!"
                uploadSuccess = "Uploaded '\(activeUploadFileName)' to \(activeUploadTargetTitle)!"
                uploadHistory.insert(
                    MTProtoUploadLogItem(fileName: activeUploadFileName, targetTitle: activeUploadTargetTitle, status: "Published via MTProto", isCompleted: true, isFailed: false),
                    at: 0
                )
                activeUploadFileId = nil
                activeUploadMessageId = nil
            }
        case .updateMessageSendFailed(let failUpd):
            if activeUploadMessageId == failUpd.oldMessageId {
                isUploading = false
                uploadError = "Send failed: \(failUpd.error.message)"
                uploadHistory.insert(
                    MTProtoUploadLogItem(fileName: activeUploadFileName, targetTitle: activeUploadTargetTitle, status: "Failed: \(failUpd.error.message)", isCompleted: false, isFailed: true),
                    at: 0
                )
                activeUploadFileId = nil
                activeUploadMessageId = nil
            }
        default:
            break
        }
    }

    private func handleAuthState(_ state: AuthorizationState) {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            sendTdlibParameters()
        case .authorizationStateWaitPhoneNumber:
            isSendingParameters = false
            authStage = .waitPhoneNumber
            if let pending = pendingPhoneNumberToSend {
                pendingPhoneNumberToSend = nil
                submitPhoneNumber(pending)
            } else {
                isBusyAuth = false
                authMessage = "Ready! Enter your mobile number and tap Send OTP Verification Code."
            }
        case .authorizationStateWaitCode:
            isSendingParameters = false
            isBusyAuth = false
            authStage = .waitCode
            authMessage = "OTP code sent! Check your Telegram app or SMS."
        case .authorizationStateWaitPassword(let pwdState):
            isSendingParameters = false
            isBusyAuth = false
            authStage = .waitPassword(hint: pwdState.passwordHint)
            authMessage = "Enter your Telegram 2FA Cloud Password."
        case .authorizationStateReady:
            isSendingParameters = false
            isBusyAuth = false
            pendingPhoneNumberToSend = nil
            authStage = .ready
            authError = nil
            authMessage = "Connected via Telegram MTProto!"
            fetchCurrentUserAndChats()
        case .authorizationStateClosed:
            isSendingParameters = false
            isBusyAuth = false
            client = nil
            authStage = .disconnected
        default:
            break
        }
    }

    private func sendTdlibParameters() {
        guard let td = client, !isSendingParameters else { return }
        isSendingParameters = true
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dbDir = appSupport.appendingPathComponent("tdlib_db", isDirectory: true)
        let filesDir = appSupport.appendingPathComponent("tdlib_files", isDirectory: true)
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)

        Task {
            do {
                _ = try await td.setTdlibParameters(
                    apiHash: currentApiHash,
                    apiId: currentApiId,
                    applicationVersion: "1.3.2",
                    databaseDirectory: dbDir.path,
                    databaseEncryptionKey: Data(),
                    deviceModel: UIDevice.current.model,
                    filesDirectory: filesDir.path,
                    systemLanguageCode: "en",
                    systemVersion: UIDevice.current.systemVersion,
                    useChatInfoDatabase: true,
                    useFileDatabase: true,
                    useMessageDatabase: true,
                    useSecretChats: false,
                    useTestDc: false
                )
            } catch {
                self.isSendingParameters = false
                self.isBusyAuth = false
                self.pendingPhoneNumberToSend = nil
                self.authError = "TDLib init error: \(error.localizedDescription)"
                self.authStage = .disconnected
            }
        }
    }

    private func fetchCurrentUserAndChats() {
        guard let td = client else { return }
        Task {
            if let me = try? await td.getMe() {
                let fullName = [me.firstName, me.lastName].filter { !$0.isEmpty }.joined(separator: " ")
                self.connectedUserName = fullName.isEmpty ? "Telegram User" : fullName
                self.connectedPhone = me.phoneNumber.isEmpty ? "" : "+\(me.phoneNumber)"
            }
            self.loadUserChats()
        }
    }

    private func handleFileUpdate(_ file: File) {
        // 1. Download progress tracking
        if let activeId = activeDownloadFileId, file.id == activeId {
            let total = max(file.size, file.expectedSize, 1)
            let downloaded = file.local.downloadedSize
            let pct = min(1.0, max(0.0, Double(downloaded) / Double(total)))
            let elapsed = max(0.1, Foundation.Date().timeIntervalSince(downloadStartTime))
            let speedKBps = (Double(downloaded) / 1024.0) / elapsed

            self.downloadProgress = pct
            self.downloadDetailText = String(
                format: "%d%% (%.1f MB / %.1f MB)",
                Int(pct * 100),
                Double(downloaded) / (1024 * 1024),
                Double(total) / (1024 * 1024)
            )
            self.downloadSpeedText = speedKBps >= 1024
                ? String(format: "%.2f MB/s", speedKBps / 1024.0)
                : String(format: "%.0f KB/s", speedKBps)

            if file.local.isDownloadingCompleted && !file.local.path.isEmpty {
                let sourceURL = URL(fileURLWithPath: file.local.path)
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let downloadsDir = docs.appendingPathComponent("Downloads", isDirectory: true)
                try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)

                let finalName = activeDownloadTargetName.isEmpty ? sourceURL.lastPathComponent : activeDownloadTargetName
                let destURL = downloadsDir.appendingPathComponent(finalName)
                try? FileManager.default.removeItem(at: destURL)
                do {
                    try FileManager.default.copyItem(at: sourceURL, to: destURL)
                    self.lastDownloadedURL = destURL
                    self.downloadDetailText = "100% Completed • Saved to Files → Downloads"
                } catch {
                    self.downloadError = "Save error: \(error.localizedDescription)"
                }
                self.isDownloading = false
                self.activeDownloadFileId = nil
            }
        }

        // 2. Upload progress tracking
        if isUploading, (activeUploadFileId == nil || activeUploadFileId == file.id), file.remote.isUploadingActive {
            activeUploadFileId = file.id
            let total = max(file.size, file.expectedSize, 1)
            let uploaded = file.remote.uploadedSize
            let pct = min(1.0, max(0.0, Double(uploaded) / Double(total)))
            let elapsed = max(0.1, Foundation.Date().timeIntervalSince(uploadStartTime))
            let speedKBps = (Double(uploaded) / 1024.0) / elapsed

            self.uploadProgress = pct
            self.uploadStatusText = String(
                format: "%d%% (%.1f MB / %.1f MB)",
                Int(pct * 100),
                Double(uploaded) / (1024 * 1024),
                Double(total) / (1024 * 1024)
            )
            self.uploadSpeedText = speedKBps >= 1024
                ? String(format: "%.2f MB/s", speedKBps / 1024.0)
                : String(format: "%.0f KB/s", speedKBps)
        }
    }

    private func extractVideo(from msg: Message, defaultProtected: Bool) -> MTProtoVideoMessage? {
        let protectedFlag = defaultProtected || !msg.canBeSaved
        switch msg.content {
        case .messageVideo(let mv):
            let v = mv.video
            let rawName = v.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackName = "video_\(msg.id).mp4"
            let finalName = rawName.isEmpty ? fallbackName : rawName
            return MTProtoVideoMessage(
                id: msg.id,
                chatId: msg.chatId,
                fileId: v.video.id,
                fileName: finalName,
                caption: mv.caption.text,
                sizeBytes: max(v.video.size, v.video.expectedSize),
                durationSeconds: v.duration,
                isProtected: protectedFlag
            )
        case .messageDocument(let md):
            let doc = md.document
            let lowerName = doc.fileName.lowercased()
            let isVideoMime = doc.mimeType.lowercased().hasPrefix("video/")
            let isVideoExt = ["mp4", "mkv", "mov", "avi", "webm", "m4v"].contains((lowerName as NSString).pathExtension)
            guard isVideoMime || isVideoExt else { return nil }
            let finalName = doc.fileName.isEmpty ? "video_\(msg.id).mp4" : doc.fileName
            return MTProtoVideoMessage(
                id: msg.id,
                chatId: msg.chatId,
                fileId: doc.document.id,
                fileName: finalName,
                caption: md.caption.text,
                sizeBytes: max(doc.document.size, doc.document.expectedSize),
                durationSeconds: 0,
                isProtected: protectedFlag
            )
        default:
            return nil
        }
    }
}
