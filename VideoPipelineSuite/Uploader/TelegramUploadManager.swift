import Foundation
import AVFoundation
import UIKit

struct VideoAssetMetadata {
    let url: URL
    let fileName: String
    let fileSizeBytes: Int64
    let durationSeconds: Double
    let width: Int
    let height: Int
    let resolutionText: String
    let thumbnail: UIImage?
}

enum VideoInspector {
    static func inspectVideo(url: URL) async -> VideoAssetMetadata {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let asset = AVURLAsset(url: url)
        var durSec: Double = 0
        if let d = try? await asset.load(.duration) {
            let s = CMTimeGetSeconds(d)
            if s.isFinite { durSec = s }
        }

        var vidW = 1280
        var vidH = 720
        var resText = "HD Video"
        if let tracks = try? await asset.loadTracks(withMediaType: .video), let first = tracks.first {
            if let naturalSize = try? await first.load(.naturalSize),
               let transform = try? await first.load(.preferredTransform) {
                let transformed = naturalSize.applying(transform)
                let w = Int(abs(transformed.width))
                let h = Int(abs(transformed.height))
                if w > 0 && h > 0 {
                    vidW = w
                    vidH = h
                    resText = "\(w)×\(h)"
                }
            }
        }

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 320)
        let thumbTime = CMTime(seconds: min(2.0, durSec * 0.2), preferredTimescale: 600)
        var thumb: UIImage? = nil
        if let cg = try? gen.copyCGImage(at: thumbTime, actualTime: nil) {
            thumb = UIImage(cgImage: cg)
        }

        return VideoAssetMetadata(
            url: url,
            fileName: url.lastPathComponent,
            fileSizeBytes: size,
            durationSeconds: durSec,
            width: vidW,
            height: vidH,
            resolutionText: resText,
            thumbnail: thumb
        )
    }
}
