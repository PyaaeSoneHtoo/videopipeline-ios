# Video Pipeline Suite (iOS Native Unsigned IPA & macOS v1.4.0)

<p align="center">
  <b>High-Performance All-in-One iOS & macOS Video Automation Suite</b><br>
  Built with SwiftUI, AVFoundation, CryptoKit, and compiled automatically via GitHub Actions (macOS Xcode).
</p>

[![Version](https://img.shields.io/badge/version-v1.4.0-blue.svg)](https://videopipeline.myanmardev.com/download.html)
[![Platform](https://img.shields.io/badge/platform-iOS%2015.0+%20|%20macOS%2012+-green.svg)](https://videopipeline.myanmardev.com/download.html)

---

## 📱 Features & Highlights (v1.4.0)

1. **🔐 Firebase Authentication & Device Slot Binding**
   - Authenticates securely via Firebase Authentication REST API.
   - Binds to a unique iOS hardware fingerprint (`DEV-IOS-XXXX`).
   - Validates active license expiration date in real time.

2. **⚙️ Pre-Configured Telegram MTProto Credentials**
   - Built-in default Telegram Application API ID (`33821639`) and API Hash.
   - Ready to run without requiring manual developer registration on `my.telegram.org`.

3. **🏷️ Batch Video Renamer**
   - **Strip Message IDs**: Removes Telegram message ID noise (`_1234`, `[1234]`) while preserving series episode numbers.
   - **Fast Regex**: Instant 0-cost series formatting (`Series Ep - 01.mp4`).
   - **Google Gemini AI**: Smart drama/anime title detection and sanitization.
   - **Direct iOS Files Renaming**: Uses native iOS Document Picker to rename files in-place.

4. **✂️ Lossless Video Intro Trimmer (Ad Cutter)**
   - Uses native `AVAssetExportPresetPassthrough` for instant stream-copy trimming with **zero quality loss** and **no re-encoding**.
   - Integrated `AVPlayer` preview with `Current Pos` timestamp capture.
   - Saves directly to Apple Files (`On My iPhone → Video Pipeline → Trimmed`) and supports one-tap **Save to Photos** or **Share**.

5. **📥 Telegram & Direct Downloader**
   - Streams video downloads directly to Apple Files (`On My iPhone → Video Pipeline → Downloads`) with live progress percentage, MB counter, and KB/s speed.

6. **📺 YouTube Downloader**
   - Extracts video ID, fetches oEmbed title & channel metadata, and exports MP4/MP3 files.

---

## 🚀 Automated GitHub Actions Compiler

Every push to `main` or version tag (`v*`) triggers `.github/workflows/build-ipa.yml` on `macos-15`:
1. Generates `VideoPipelineSuite.xcodeproj` with **XcodeGen** (`project.yml`).
2. Compiles the Release `arm64` binary with `CODE_SIGNING_ALLOWED=NO`.
3. Packages `Payload/VideoPipelineSuite.app` into `VideoPipelineSuite-v1.4.0-unsigned.ipa`.
4. Builds native macOS disk image `VideoPipelineSuite-v1.4.0-macos.dmg`.
5. Uploads and publishes artifacts to **GitHub Releases**:
   👉 [https://videopipeline.myanmardev.com/download.html](https://videopipeline.myanmardev.com/download.html)

### 📲 Installing the Unsigned IPA on iOS
- **TrollStore**: Direct permanent installation without signing (iOS 14.0–15.4.1 / 16.0–16.6.1).
- **AltStore / SideStore / Sideloadly**: Sign with your personal free Apple ID and sideload directly over Wi-Fi/USB.
- **ESign / Scarlet / Feather**: Sign with your corporate or developer distribution certificate.
