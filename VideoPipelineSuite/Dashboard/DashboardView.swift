import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var session: UserSession
    @ObservedObject private var api = ApiSettingsStore.shared
    @ObservedObject private var mtproto = TelegramMTProtoManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.bgDark.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Top Brand & Settings Header
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Video Pipeline Suite")
                                    .font(.title2.bold())
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("iOS MTProto Studio • v1.3.0")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            Spacer()
                            NavigationLink(destination: ApiSetupView()) {
                                Image(systemName: "key.fill")
                                    .font(.subheadline)
                                    .foregroundColor(AppTheme.amber)
                                    .padding(10)
                                    .background(AppTheme.surfaceCard)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(AppTheme.surfaceCardBorder, lineWidth: 1))
                            }
                            NavigationLink(destination: SettingsView()) {
                                Image(systemName: "gearshape.fill")
                                    .font(.title3)
                                    .foregroundColor(AppTheme.textPrimary)
                                    .padding(10)
                                    .background(AppTheme.surfaceCard)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(AppTheme.surfaceCardBorder, lineWidth: 1))
                            }
                        }

                        // License Status Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(session.email.isEmpty ? "user@example.com" : session.email)
                                    .font(.headline)
                                    .foregroundColor(AppTheme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text("ACTIVE")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.emerald.opacity(0.2))
                                    .foregroundColor(AppTheme.emerald)
                                    .clipShape(Capsule())
                            }

                            HStack {
                                Label("Valid Until: \(session.expiresAt)", systemImage: "calendar")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Text("iOS Slot Bound")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(AppTheme.primaryLight)
                            }
                        }
                        .pipelineCard()

                        // Hero 2-Column Studio Cards: Downloader & Uploader
                        HStack(spacing: 12) {
                            NavigationLink(destination: TelegramDownloaderView()) {
                                heroStudioTile(
                                    title: "Downloader",
                                    subtitle: "Telegram & Direct",
                                    icon: "arrow.down.circle.fill",
                                    gradient: [AppTheme.cyan, AppTheme.emerald]
                                )
                            }

                            NavigationLink(destination: UploaderStudioView()) {
                                heroStudioTile(
                                    title: "Uploader",
                                    subtitle: "Telegram & TikTok",
                                    icon: "arrow.up.circle.fill",
                                    gradient: [AppTheme.primary, AppTheme.cyan]
                                )
                            }
                        }

                        // API & Telegram Quick Status Bar
                        NavigationLink(destination: ApiSetupView()) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label("API Keys & Telegram Login", systemImage: "key.horizontal.fill")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(AppTheme.textPrimary)
                                    Spacer()
                                    Text("Setup →")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(AppTheme.primaryLight)
                                }
                                HStack(spacing: 8) {
                                    apiPill(name: "MTProto", active: mtproto.isAuthorized)
                                    apiPill(name: "Gemini", active: api.hasGeminiKey)
                                    apiPill(name: "DeepSeek", active: api.hasDeepSeekKey)
                                }
                            }
                            .pipelineCard(cornerRadius: 14, padding: 14)
                        }

                        // Additional Suite Tools Header
                        HStack {
                            Text("AI & Media Tools")
                                .font(.headline)
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                        }
                        .padding(.top, 2)

                        // Tool Navigation Cards
                        VStack(spacing: 12) {
                            NavigationLink(destination: VideoTrimmerView()) {
                                toolCard(
                                    title: "AI Ad Cutter & Lossless Trimmer",
                                    subtitle: "Gemini/DeepSeek intro ad scan + instant lossless cut",
                                    icon: "scissors",
                                    accent: AppTheme.emerald
                                )
                            }

                            NavigationLink(destination: BatchRenamerView()) {
                                toolCard(
                                    title: "Batch Video Renamer",
                                    subtitle: "Strip Telegram IDs, Fast Regex, Gemini & DeepSeek AI",
                                    icon: "tag.fill",
                                    accent: AppTheme.primaryLight
                                )
                            }

                            NavigationLink(destination: YouTubeDownloaderView()) {
                                toolCard(
                                    title: "YouTube Downloader",
                                    subtitle: "HD thumbnail preview + MP4 / MP3 stream export",
                                    icon: "play.rectangle.fill",
                                    accent: AppTheme.danger
                                )
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }

    private func heroStudioTile(title: String, subtitle: String, icon: String, gradient: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(.white)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.bold())
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: gradient.first?.opacity(0.28) ?? .clear, radius: 12, x: 0, y: 6)
    }

    private func apiPill(name: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
            Text(name)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((active ? AppTheme.emerald : AppTheme.textMuted).opacity(0.16))
        .foregroundColor(active ? AppTheme.emerald : AppTheme.textSecondary)
        .clipShape(Capsule())
    }

    private func toolCard(title: String, subtitle: String, icon: String, accent: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(accent.opacity(0.16))
                    .frame(width: 50, height: 50)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textMuted)
        }
        .pipelineCard(cornerRadius: 16, padding: 14)
    }
}
