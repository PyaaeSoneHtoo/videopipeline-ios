import Foundation
import AVFoundation

enum VideoTrimmerEngine {
    static func trimLossless(
        inputURL: URL,
        outputURL: URL,
        startSeconds: Double,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        guard totalSeconds.isFinite, startSeconds < totalSeconds else {
            throw NSError(
                domain: "VideoTrimmerEngine",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cut time (\(String(format: "%.1f", startSeconds))s) must be less than video duration (\(String(format: "%.1f", totalSeconds))s)."]
            )
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw NSError(
                domain: "VideoTrimmerEngine",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to initialize lossless AVAssetExportSession."]
            )
        }

        let startTime = CMTime(seconds: startSeconds, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startTime, end: duration)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = timeRange
        exportSession.shouldOptimizeForNetworkUse = true

        // Poll progress while exporting
        let progressTask = Task {
            while !Task.isCancelled {
                onProgress(Double(exportSession.progress))
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        await exportSession.export()
        progressTask.cancel()

        switch exportSession.status {
        case .completed:
            onProgress(1.0)
            return outputURL
        case .failed:
            throw exportSession.error ?? NSError(
                domain: "VideoTrimmerEngine",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Lossless trim export failed."]
            )
        case .cancelled:
            throw NSError(
                domain: "VideoTrimmerEngine",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Export cancelled."]
            )
        default:
            throw NSError(
                domain: "VideoTrimmerEngine",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected export status."]
            )
        }
    }
}
