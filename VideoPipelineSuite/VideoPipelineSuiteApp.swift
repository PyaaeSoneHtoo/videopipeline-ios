import SwiftUI

@main
struct VideoPipelineSuiteApp: App {
    @StateObject private var session = UserSession.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isLoggedIn {
                    DashboardView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(session)
            .preferredColorScheme(.dark)
        }
    }
}
