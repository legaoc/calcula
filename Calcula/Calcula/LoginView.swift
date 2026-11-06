import SwiftUI

/// Login y registro con email y contraseña (igual que la web).
struct LoginView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var localError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 60)

                VStack(spacing: 8) {
                    Image("CalculaWordmarkLarge")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 44)
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Calcula")
                    Text("Tus gastos, en orden")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    if isSignUp {
                        TextField("Nombre", text: $name)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                    }
                    TextField("Correo electrónico", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    SecureField("Contraseña", text: $password)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)

                    if let message = auth.errorMessage ?? localError {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if auth.isBusy {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(isSignUp ? "Crear cuenta" : "Entrar")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.calculaAccent)
                    .disabled(auth.isBusy)

                    Button(isSignUp ? "¿Ya tienes cuenta? Entra" : "¿No tienes cuenta? Regístrate") {
                        isSignUp.toggle()
                        auth.errorMessage = nil
                        localError = nil
                    }
                    .font(.footnote)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .background(Color.calculaBackground)
    }

    private func submit() async {
        localError = nil
        let cleanEmail = email.trimmingCharacters(in: .whitespaces)
        guard !cleanEmail.isEmpty, password.count >= 6 else {
            localError = "Escribe correo y una contraseña de 6+ caracteres"
            return
        }
        if isSignUp {
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                localError = "Escribe tu nombre"
                return
            }
            await auth.signUp(name: name, email: cleanEmail, password: password)
        } else {
            await auth.signIn(email: cleanEmail, password: password)
        }
    }
}
