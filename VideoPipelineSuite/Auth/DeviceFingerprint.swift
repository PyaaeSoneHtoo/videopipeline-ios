import Foundation
import CryptoKit
import UIKit

enum DeviceFingerprint {
    private static let persistedKey = "vp_ios_persisted_device_seed"

    static func getDeviceId() -> String {
        let seed: String
        if let saved = UserDefaults.standard.string(forKey: persistedKey), !saved.isEmpty {
            seed = saved
        } else {
            let vendorId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            UserDefaults.standard.set(vendorId, forKey: persistedKey)
            seed = vendorId
        }

        let digest = SHA256.hash(data: Data(seed.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let shortHash = String(hex.prefix(12)).uppercased()
        return "DEV-IOS-\(shortHash)"
    }
}
