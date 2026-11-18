import Foundation

struct AuthResult {
    let success: Bool
    var token: String? = nil
    var uid: String? = nil
    var email: String? = nil
    var expiresAt: String? = nil
    var plan: String = "VIP License (1 PC + 1 Mobile)"
    var boundDeviceId: String? = nil
    var errorMessage: String? = nil
}

enum AuthService {
    private static let firebaseApiKey = "AIzaSyDDTgn3xb76GgMEkpW2fq9H_NFZBX_5imU"
    private static let signInURL = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(firebaseApiKey)")!
    private static let lookupURL = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=\(firebaseApiKey)")!
    private static let updateURL = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:update?key=\(firebaseApiKey)")!

    static func signIn(email: String, password: String, deviceId: String) async -> AuthResult {
        do {
            // 1. Authenticate with Firebase REST API
            let signInPayload: [String: Any] = [
                "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
                "password": password.trimmingCharacters(in: .whitespacesAndNewlines),
                "returnSecureToken": true
            ]

            let (signInData, signInResponse) = try await postJSON(url: signInURL, payload: signInPayload)
            let signInJSON = (try? JSONSerialization.jsonObject(with: signInData) as? [String: Any]) ?? [:]
            let statusCode = (signInResponse as? HTTPURLResponse)?.statusCode ?? 0

            if statusCode < 200 || statusCode >= 300 {
                let errObj = signInJSON["error"] as? [String: Any]
                let message = errObj?["message"] as? String ?? "Authentication failed (\(statusCode))"
                let friendly: String
                if message.contains("EMAIL_NOT_FOUND") {
                    friendly = "No account found with this email."
                } else if message.contains("INVALID_PASSWORD") || message.contains("INVALID_LOGIN_CREDENTIALS") {
                    friendly = "Incorrect email or password. Please try again."
                } else if message.contains("USER_DISABLED") {
                    friendly = "Your account has been suspended or expired."
                } else if message.contains("TOO_MANY_ATTEMPTS_TRY_LATER") {
                    friendly = "Too many failed attempts. Try again later."
                } else {
                    friendly = message
                }
                return AuthResult(success: false, errorMessage: friendly)
            }

            let idToken = signInJSON["idToken"] as? String ?? ""
            let localId = signInJSON["localId"] as? String ?? ""
            let userEmail = signInJSON["email"] as? String ?? email.trimmingCharacters(in: .whitespacesAndNewlines)

            // 2. Lookup profile metadata
            var rawDisplayName = ""
            var customClaimsStr = ""

            if let (lookupData, lookupResponse) = try? await postJSON(url: lookupURL, payload: ["idToken": idToken]),
               let httpResp = lookupResponse as? HTTPURLResponse,
               (200..<300).contains(httpResp.statusCode),
               let lookupJSON = try? JSONSerialization.jsonObject(with: lookupData) as? [String: Any],
               let users = lookupJSON["users"] as? [[String: Any]],
               let firstUser = users.first {
                rawDisplayName = firstUser["displayName"] as? String ?? ""
                customClaimsStr = firstUser["customAttributes"] as? String ?? ""
            }

            // 3. Parse expiration date
            var expiresAt = "2026-12-31"
            if let match = firstMatch(pattern: "(?:expire|until|exp)[:=\\s]*([0-9\\-]+)", in: rawDisplayName) {
                expiresAt = match
            } else if !customClaimsStr.isEmpty,
                      let claimsData = customClaimsStr.data(using: .utf8),
                      let claimsJSON = try? JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
                      let expClaim = claimsJSON["expire_date"] as? String, !expClaim.isEmpty {
                expiresAt = expClaim
            }

            // Validate expiration date
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            if let expDate = df.date(from: expiresAt) {
                let endOfExpDay = Calendar.current.date(byAdding: .day, value: 1, to: expDate) ?? expDate
                if endOfExpDay < Date() {
                    return AuthResult(
                        success: false,
                        errorMessage: "Subscription Expired: Your plan expired on \(expiresAt). Please renew your license on the website."
                    )
                }
            }

            // 4. Plan-Based iOS Eligibility Check (Personal 1 PC = No iOS; Team 2 PCs & Business 3 PCs = 1 iOS Included)
            var maxDevices = 1
            var explicitMaxIos: Int? = nil
            var boundIosId: String? = nil

            if !customClaimsStr.isEmpty,
               let claimsData = customClaimsStr.data(using: .utf8),
               let claimsJSON = try? JSONSerialization.jsonObject(with: claimsData) as? [String: Any] {
                if let md = claimsJSON["max_devices"] as? Int {
                    maxDevices = md
                } else if let mdNum = claimsJSON["max_devices"] as? NSNumber {
                    maxDevices = mdNum.intValue
                }
                if let mi = claimsJSON["max_ios_devices"] as? Int {
                    explicitMaxIos = mi
                } else if let miNum = claimsJSON["max_ios_devices"] as? NSNumber {
                    explicitMaxIos = miNum.intValue
                }
                if let d = claimsJSON["ios_device_id"] as? String {
                    let trimmed = d.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && trimmed.lowercased() != "unbound" && trimmed.lowercased() != "null" && trimmed.lowercased() != "disabled" {
                        boundIosId = trimmed
                    }
                }
            }

            if let mdMatch = firstMatch(pattern: "(?:maxdev|max_dev|max_devices)[:=\\s]*([1-3])", in: rawDisplayName),
               let parsedMd = Int(mdMatch) {
                maxDevices = parsedMd
            }

            let iosDisabledInDisplay = rawDisplayName.range(of: "ios:DISABLED", options: .caseInsensitive) != nil
                || rawDisplayName.range(of: "ios:NONE", options: .caseInsensitive) != nil

            let isIosAllowed: Bool
            if let explicit = explicitMaxIos {
                isIosAllowed = explicit >= 1 && !iosDisabledInDisplay
            } else {
                isIosAllowed = maxDevices >= 2 && !iosDisabledInDisplay
            }

            if !isIosAllowed {
                return AuthResult(
                    success: false,
                    errorMessage: "iOS App Not Included in Personal Plan: Your current Personal (1 PC) license includes 1 PC + 1 Android device only. Upgrade to a Team (2 PCs) or Business (3 PCs) plan to unlock the iOS App."
                )
            }

            if boundIosId == nil,
               let match = firstMatch(pattern: "(?:ios|ios_dev|ios_id)[:=\\s]*([a-zA-Z0-9_\\-]+)", in: rawDisplayName) {
                let trimmed = match.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed.lowercased() != "unbound" && trimmed.lowercased() != "null" && trimmed.lowercased() != "disabled" && trimmed != "1" {
                    boundIosId = trimmed
                }
            }

            let currentClean = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

            if let existingBound = boundIosId {
                let boundClean = existingBound.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if boundClean != currentClean {
                    return AuthResult(
                        success: false,
                        errorMessage: "iOS Device Limit Exceeded: This account is already bound to another iOS device (\(boundClean)). Only 1 iOS device is accepted per Team/Business license. Please contact administrator to reset your device slot."
                    )
                }
            } else {
                // Auto-bind iOS device slot
                let updatedDisplayName: String
                if rawDisplayName.range(of: "ios:", options: .caseInsensitive) != nil {
                    updatedDisplayName = replacingRegex(
                        pattern: "(?:ios|ios_dev|ios_id)[:=\\s]*[a-zA-Z0-9_\\-]+",
                        in: rawDisplayName,
                        with: "ios:\(currentClean)"
                    )
                } else if !rawDisplayName.isEmpty {
                    updatedDisplayName = "\(rawDisplayName) | ios:\(currentClean)"
                } else {
                    let prefix = userEmail.components(separatedBy: "@").first ?? "user"
                    updatedDisplayName = "\(prefix) | expire:\(expiresAt) | maxdev:\(maxDevices) | ios:\(currentClean)"
                }

                let updatePayload: [String: Any] = [
                    "idToken": idToken,
                    "displayName": updatedDisplayName,
                    "returnSecureToken": true
                ]
                _ = try? await postJSON(url: updateURL, payload: updatePayload)
                boundIosId = currentClean
            }

            let planLabel = maxDevices >= 3
                ? "Business Plan (3 PCs + 1 Android + 1 iOS)"
                : "Team Plan (2 PCs + 1 Android + 1 iOS)"

            return AuthResult(
                success: true,
                token: idToken,
                uid: localId,
                email: userEmail,
                expiresAt: expiresAt,
                plan: planLabel,
                boundDeviceId: boundIosId ?? currentClean
            )
        } catch {
            return AuthResult(
                success: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    private static func postJSON(url: URL, payload: [String: Any]) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await URLSession.shared.data(for: req)
    }

    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func replacingRegex(pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: nsRange, withTemplate: template)
    }
}
