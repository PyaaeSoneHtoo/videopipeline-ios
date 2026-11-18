import Foundation
import Combine

@MainActor
final class UserSession: ObservableObject {
    static let shared = UserSession()

    private enum Keys {
        static let isLoggedIn = "vp_is_logged_in"
        static let idToken = "vp_id_token"
        static let localId = "vp_local_id"
        static let email = "vp_email"
        static let expiresAt = "vp_expires_at"
        static let plan = "vp_plan"
        static let deviceId = "vp_device_id"
    }

    @Published var isLoggedIn: Bool
    @Published var idToken: String
    @Published var localId: String
    @Published var email: String
    @Published var expiresAt: String
    @Published var plan: String
    @Published var deviceId: String

    private init() {
        let defaults = UserDefaults.standard
        self.isLoggedIn = defaults.bool(forKey: Keys.isLoggedIn)
        self.idToken = defaults.string(forKey: Keys.idToken) ?? ""
        self.localId = defaults.string(forKey: Keys.localId) ?? ""
        self.email = defaults.string(forKey: Keys.email) ?? ""
        self.expiresAt = defaults.string(forKey: Keys.expiresAt) ?? "2026-12-31"
        self.plan = defaults.string(forKey: Keys.plan) ?? "VIP License"
        self.deviceId = defaults.string(forKey: Keys.deviceId) ?? DeviceFingerprint.getDeviceId()
    }

    func saveLogin(
        token: String,
        uid: String,
        emailAddress: String,
        expiry: String,
        device: String,
        userPlan: String = "VIP License"
    ) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Keys.isLoggedIn)
        defaults.set(token, forKey: Keys.idToken)
        defaults.set(uid, forKey: Keys.localId)
        defaults.set(emailAddress, forKey: Keys.email)
        defaults.set(expiry, forKey: Keys.expiresAt)
        defaults.set(device, forKey: Keys.deviceId)
        defaults.set(userPlan, forKey: Keys.plan)

        self.isLoggedIn = true
        self.idToken = token
        self.localId = uid
        self.email = emailAddress
        self.expiresAt = expiry
        self.deviceId = device
        self.plan = userPlan
    }

    func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.isLoggedIn)
        defaults.removeObject(forKey: Keys.idToken)
        defaults.removeObject(forKey: Keys.localId)
        defaults.removeObject(forKey: Keys.email)
        defaults.removeObject(forKey: Keys.expiresAt)
        defaults.removeObject(forKey: Keys.plan)
        defaults.removeObject(forKey: Keys.deviceId)

        self.isLoggedIn = false
        self.idToken = ""
        self.localId = ""
        self.email = ""
        self.expiresAt = "2026-12-31"
        self.plan = "VIP License"
        self.deviceId = DeviceFingerprint.getDeviceId()
    }
}
