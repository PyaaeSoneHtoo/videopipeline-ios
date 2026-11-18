import SwiftUI
import UniformTypeIdentifiers

struct BatchRenamerView: View {
    @ObservedObject private var api = ApiSettingsStore.shared
    @State private var items: [RenameItem] = []
    @State private var selectedFolderURL: URL? = nil
    @State private var folderTitle: String = "No Folder Selected"
    @State private var showFolderPicker: Bool = false
    @State private var isProcessing: Bool = false
    @State private var statusBanner: String? = nil

    private let videoExtensions: Set<String> = ["mp4", "mkv", "avi", "mov", "flv", "ts", "webm", "m4v"]

    var body: some View {
        ZStack {
            AppTheme.bgDark.ignoresSafeArea()

            VStack(spacing: 14) {
                // Folder Selector Card
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.primary.opacity(0.18))
                            .frame(width: 46, height: 46)
                        Image(systemName: "folder.fill")
                            .foregroundColor(AppTheme.primaryLight)
                            .font(.title3)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(folderTitle)
                            .font(.headline)
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                        Text("\(items.count) video files loaded")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    Spacer()

                    Button("Browse") {
                        showFolderPicker = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppTheme.primary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .pipelineCard(padding: 14)

                // Preset Action Bar
                HStack(spacing: 8) {
                    presetChip(title: "Strip ID", icon: "wand.and.stars", color: AppTheme.cyan) {
                        applyStripMsgIds()
                    }
                    presetChip(title: "Regex", icon: "textformat.123", color: AppTheme.amber) {
                        applyRegexPreset()
                    }
                    presetChip(title: "Gemini", icon: "sparkles", color: AppTheme.primaryLight) {
                        applyAI(provider: .gemini)
                    }
                    presetChip(title: "DeepSeek", icon: "brain", color: AppTheme.emerald) {
                        applyAI(provider: .deepseek)
                    }
                }
                .disabled(items.isEmpty || isProcessing)

                if !api.hasGeminiKey && !api.hasDeepSeekKey {
                    NavigationLink(destination: ApiSetupView()) {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .foregroundColor(AppTheme.amber)
                            Text("Import Gemini or DeepSeek API Key to enable AI Renaming")
                                .font(.caption.weight(.medium))
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .padding(10)
                        .background(AppTheme.amber.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                if isProcessing {
                    ProgressView("Processing...")
                        .tint(AppTheme.primaryLight)
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.vertical, 6)
                }

                if let banner = statusBanner {
                    Text(banner)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(AppTheme.emerald)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.emerald.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // File Preview List
                if items.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 44))
                            .foregroundColor(AppTheme.textMuted)
                        Text("Select a folder from iOS Files")
                            .font(.headline)
                            .foregroundColor(AppTheme.textSecondary)
                        Text("Clean Telegram IDs (_1234), unify series episode numbers, or auto-organize with Gemini AI.")
                            .font(.caption)
                            .foregroundColor(AppTheme.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(items) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(item.originalName)
                                            .font(.caption)
                                            .foregroundColor(AppTheme.textMuted)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(item.status)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(statusColor(item.status).opacity(0.18))
                                            .foregroundColor(statusColor(item.status))
                                            .clipShape(Capsule())
                                    }

                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.turn.down.right")
                                            .font(.caption)
                                            .foregroundColor(AppTheme.emerald)
                                        Text(item.newName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(AppTheme.textPrimary)
                                            .lineLimit(2)
                                    }
                                }
                                .pipelineCard(cornerRadius: 12, padding: 12)
                            }
                        }
                    }
                }

                // Apply Rename Button
                Button {
                    executeRenameOnDisk()
                } label: {
                    Label("Apply Rename to \(items.count) Files", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: AppTheme.emerald))
                .disabled(items.isEmpty || isProcessing)
            }
            .padding(16)
        }
        .navigationTitle("Batch Video Renamer")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let folder = urls.first {
                    loadFolder(folder)
                }
            case .failure(let error):
                statusBanner = "Folder error: \(error.localizedDescription)"
            }
        }
    }

    private func presetChip(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.16))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Renamed": return AppTheme.emerald
        case "Failed": return AppTheme.danger
        case "Skipped": return AppTheme.textMuted
        default: return AppTheme.primaryLight
        }
    }

    private func loadFolder(_ folderURL: URL) {
        selectedFolderURL = folderURL
        folderTitle = folderURL.lastPathComponent
        statusBanner = nil
        isProcessing = true

        Task.detached(priority: .userInitiated) {
            let accessed = folderURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { folderURL.stopAccessingSecurityScopedResource() }
            }

            var loaded: [RenameItem] = []
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                let sorted = contents.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                for fileURL in sorted {
                    let ext = fileURL.pathExtension.lowercased()
                    if videoExtensions.contains(ext) {
                        let name = fileURL.lastPathComponent
                        loaded.append(RenameItem(fileURL: fileURL, originalName: name, newName: name, status: "Ready"))
                    }
                }
            }

            await MainActor.run {
                items = loaded
                isProcessing = false
                if !items.isEmpty {
                    applyStripMsgIds()
                }
            }
        }
    }

    private func applyStripMsgIds() {
        for idx in items.indices {
            items[idx].newName = RenamerEngine.removeMessageIdOnly(items[idx].originalName)
            items[idx].status = "Ready"
        }
        statusBanner = "Preview updated: Telegram Message IDs stripped."
    }

    private func applyRegexPreset() {
        let stems = items.map { RenamerEngine.stripTelegramMessageId($0.originalName).stem }
        let series = RenamerEngine.cleanSeriesTitleHeuristic(stems)
        for idx in items.indices {
            items[idx].newName = RenamerEngine.formatSingleFilenameRegex(
                originalName: items[idx].originalName,
                seriesTitle: series,
                totalCount: items.count,
                fallbackIndex: idx + 1
            )
            items[idx].status = "Ready"
        }
        statusBanner = "Preview updated: Fast Regex series format applied."
    }

    private func applyAI(provider: AIProvider) {
        isProcessing = true
        statusBanner = nil
        let snapshot = items
        let key = provider == .gemini ? api.geminiApiKey : api.deepseekApiKey
        let model = provider == .gemini ? api.geminiModel : api.deepseekModel
        let endpoint = api.deepseekEndpoint

        Task {
            let result = await GeminiRenamerService.renameWithAI(
                items: snapshot,
                provider: provider,
                apiKey: key,
                modelName: model,
                deepseekEndpoint: endpoint
            )
            items = result.items
            isProcessing = false
            statusBanner = result.note
        }
    }

    private func executeRenameOnDisk() {
        guard let folderURL = selectedFolderURL, !items.isEmpty else { return }
        isProcessing = true
        let snapshot = items

        Task.detached(priority: .userInitiated) {
            let accessed = folderURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { folderURL.stopAccessingSecurityScopedResource() }
            }

            var updated = snapshot
            var successCount = 0

            for idx in updated.indices {
                let item = updated[idx]
                if item.originalName == item.newName {
                    updated[idx].status = "Skipped"
                    continue
                }

                let destURL = item.fileURL.deletingLastPathComponent().appendingPathComponent(item.newName)
                do {
                    try FileManager.default.moveItem(at: item.fileURL, to: destURL)
                    updated[idx].status = "Renamed"
                    successCount += 1
                } catch {
                    updated[idx].status = "Failed"
                }
            }

            await MainActor.run {
                items = updated
                isProcessing = false
                statusBanner = "Renamed \(successCount) / \(updated.count) files successfully!"
            }
        }
    }
}
