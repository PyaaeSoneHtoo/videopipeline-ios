import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var session: UserSession

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.bgDark.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        // Top Brand & Settings Header
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Video Pipeline Suite")
                                    .font(.title2.bold())
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("iOS Edition • v1.0.0")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            Spacer()
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

                        // Tools Grid Header
                        HStack {
                            Text("Automation Tools")
                                .font(.headline)
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                        }
                        .padding(.top, 4)

                        // Tool Navigation Cards
                        VStack(spacing: 12) {
                            NavigationLink(destination: BatchRenamerView()) {
                                toolCard(
                                    title: "Batch Video Renamer",
                                    subtitle: "Strip Telegram IDs, Fast Regex & Gemini AI renaming",
                                    icon: "tag.fill",
                                    accent: AppTheme.primaryLight
                                )
                            }

                            NavigationLink(destination: VideoTrimmerView()) {
                                toolCard(
                                    title: "Lossless Intro Trimmer",
                                    subtitle: "Instant ad & intro cutting without re-encoding",
                                    icon: "scissors",
                                    accent: AppTheme.emerald
                                )
                            }

                            NavigationLink(destination: TelegramDownloaderView()) {
                                toolCard(
                                    title: "Telegram & Direct Downloader",
                                    subtitle: "High-speed stream downloads directly to iOS Files",
                                    icon: "paperplane.fill",
                                    accent: AppTheme.cyan
                                )
                            }

                            NavigationLink(destination: YouTubeDownloaderView()) {
                                toolCard(
                                    title: "YouTube Downloader",
                                    subtitle: "Fetch metadata & export MP4 / MP3 streams",
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

    private func toolCard(title: String, subtitle: String, icon: String, accent: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(accent.opacity(0.16))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.title2)
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
