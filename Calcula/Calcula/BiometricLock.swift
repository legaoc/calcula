import Foundation
import LocalAuthentication
import SwiftUI

/// Bloqueo con Face ID / Touch ID (con código del dispositivo como
/// respaldo), igual que la capa nativa de la versión web.
/// La preferencia vive en UserDefaults con la misma clave que la web
/// (`calcula-faceid-lock`) para que el ajuste se conserve.
@MainActor
final class BiometricLock: ObservableObject {
    @AppStorage("calcula-faceid-lock") var faceIDEnabled = false
    @Published private(set) var isLocked = false

    /// Al volver a primer plano, bloquea si el ajuste está prendido.
    func lockIfNeeded() {
        if faceIDEnabled {
            isLocked = true
        }
    }

    func unlock() {
        isLocked = false
    }

    var biometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &error
        )
    }

    /// Pide Face ID / Touch ID; si no hay biometría, cae al código.
    func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &error
        ) ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        do {
            let ok = try await context.evaluatePolicy(
                policy,
                localizedReason: "Desbloquea Calcula para ver tus gastos"
            )
            if ok { isLocked = false }
            return ok
        } catch {
            return false
        }
    }
}

/// Pantalla de bloqueo que se muestra encima de la app.
struct LockView: View {
    @EnvironmentObject private var lock: BiometricLock
    @State private var failed = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.calculaAccent)
            Text("Calcula")
                .font(.largeTitle.bold())
            Text("Tu información está bloqueada")
                .foregroundStyle(.secondary)
            Button {
                Task {
                    let ok = await lock.authenticate()
                    failed = !ok
                }
            } label: {
                Label("Desbloquear con Face ID", systemImage: "faceid")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.calculaAccent)
            .padding(.horizontal, 32)
            if failed {
                Text("No se pudo verificar tu identidad. Inténtalo de nuevo.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .background(Color.calculaBackground)
        .task {
            // Intenta desbloquear solo al aparecer.
            _ = await lock.authenticate()
        }
    }
}
