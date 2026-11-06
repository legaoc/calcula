import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Sesión de Firebase Auth (email y contraseña, mismo proyecto `psnllega`).
@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var user: User?
    @Published var errorMessage: String?
    @Published var isBusy = false

    private var listener: AuthStateDidChangeListenerHandle?

    init() {
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
            }
        }
    }

    var isSignedIn: Bool { user != nil }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Registro en 3 pasos en la web (nombre, correo, contraseña).
    /// Aquí el nombre va en el mismo formulario; se guarda como
    /// displayName de Auth y en settings/profile con los valores por
    /// defecto (el wizard completo de onboarding es etapa 2).
    func signUp(name: String, email: String, password: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            if !trimmedName.isEmpty {
                let change = result.user.createProfileChangeRequest()
                change.displayName = trimmedName
                try await change.commitChanges()
            }
            try await Firestore.firestore()
                .collection("users").document(result.user.uid)
                .collection("settings").document("profile")
                .setData([
                    "name": trimmedName,
                    "income": "fortnightly",
                    "currency": "MXN",
                    "onboardingDone": false,
                ], merge: true)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Mensajes en español para los errores comunes de Auth.
    static func message(for error: Error) -> String {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .invalidEmail:
            return "Ese correo no es válido."
        case .wrongPassword, .invalidCredential:
            return "Correo o contraseña incorrectos."
        case .userNotFound:
            return "No hay cuenta con ese correo."
        case .emailAlreadyInUse:
            return "Ese correo ya tiene cuenta."
        case .weakPassword:
            return "La contraseña debe tener al menos 6 caracteres."
        case .networkError:
            return "No se pudo conectar con Firebase, revisa tu internet e inténtalo de nuevo."
        case .tooManyRequests:
            return "Demasiados intentos. Espera un momento e inténtalo de nuevo."
        default:
            return error.localizedDescription
        }
    }
}
