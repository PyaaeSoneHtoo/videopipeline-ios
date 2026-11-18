# Video Pipeline Suite (iOS Native Unsigned IPA)

<p align="center">
  <b>High-Performance All-in-One iOS Video Automation Suite</b><br>
  Built with SwiftUI, AVFoundation, CryptoKit, and compiled automatically into an unsigned <code>.ipa</code> via GitHub Actions (macOS Xcode).
</p>

---

## 📱 Features

1. **🔐 Firebase Authentication & Device Slot Binding**
   - Authenticates securely via Firebase Authentication REST API.
   - Binds to a unique iOS hardware fingerprint (`DEV-IOS-XXXX`).
   - Validates active license expiration date.

2. **🏷️ Batch Video Renamer**
   - **Strip Message IDs**: Removes Telegram message ID noise (`_1234`, `[1234]`) while preserving series episode numbers.
   - **Fast Regex**: Instant 0-cost series formatting (`Series Ep - 01.mp4`).
   - **Google Gemini AI**: Smart drama/anime title detection and sanitization.
   - **Direct iOS Files Renaming**: Uses native iOS Document Picker to rename files in-place.

3. **✂️ Lossless Video Intro Trimmer (Ad Cutter)**
   - Uses native `AVAssetExportPresetPassthrough` for instant stream-copy trimming with **zero quality loss** and **no re-encoding**.
   - Integrated `AVPlayer` preview with `Current Pos` timestamp capture.
   - Saves directly to Apple Files (`On My iPhone → Video Pipeline → Trimmed`) and supports one-tap **Save to Photos** or **Share**.

4. **📥 Telegram & Direct Downloader**
   - Streams video downloads directly to Apple Files (`On My iPhone → Video Pipeline → Downloads`) with live progress percentage, MB counter, and KB/s speed.

5. **📺 YouTube Downloader**
   - Extracts video ID, fetches oEmbed title & channel metadata, and exports MP4/MP3 files.

---

## 🚀 Automated GitHub Actions Compiler (Unsigned IPA)

Every push to `main` or version tag (`v*`) triggers `.github/workflows/build-ipa.yml` on `macos-15`:
1. Generates `VideoPipelineSuite.xcodeproj` with **XcodeGen** (`project.yml`).
2. Compiles the Release `arm64` binary with `CODE_SIGNING_ALLOWED=NO`.
3. Packages `Payload/VideoPipelineSuite.app` into `VideoPipelineSuite-v1.0.0-unsigned.ipa`.
4. Uploads the `.ipa` as a workflow artifact and publishes it to **GitHub Releases**.

### 📲 Installing the Unsigned IPA
- **TrollStore**: Direct permanent installation without signing.
- **AltStore / SideStore / Sideloadly**: Sign with your Apple ID and sideload.
- **ESign / Scarlet / Feather**: Sign with your distribution certificate.
