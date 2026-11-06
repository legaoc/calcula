import SwiftUI
import FirebaseCore

@main
struct CalculaApp: App {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var store = DataStore()
    @StateObject private var lock = BiometricLock()
    @Environment(\.scenePhase) private var scenePhase
    /// Misma clave que la web (`calcula-dark`): "1" = modo oscuro.
    @AppStorage("calcula-dark") private var darkMode = false

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.user == nil {
                    LoginView()
                } else if lock.isLocked {
                    LockView()
                } else if store.profileLoaded && store.profile?.onboardingDone != true {
                    OnboardingView()
                } else {
                    ContentView()
                }
            }
            .environmentObject(auth)
            .environmentObject(store)
            .environmentObject(lock)
            // Acento del perfil (colors[0]), como applyTheme() en la web.
            .tint(Color(hex: store.profile?.colors.first ?? "111111"))
            .preferredColorScheme(darkMode ? .dark : .light)
            .task {
                if let uid = auth.user?.uid {
                    store.startListening(uid: uid)
                }
            }
            .onChange(of: auth.user?.uid) { _, newUID in
                if let newUID {
                    store.startListening(uid: newUID)
                } else {
                    store.stopListening()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    lock.lockIfNeeded()
                }
            }
        }
    }
}
