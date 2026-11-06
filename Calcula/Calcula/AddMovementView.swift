import SwiftUI

/// Registro rápido de movimiento (el botón "+" central del tabbar).
struct AddMovementView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAccountId: String
    @State private var kind = "cargo"
    @State private var amountText = ""
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var savedTrigger = 0

    init(preselectedAccountId: String? = nil) {
        _selectedAccountId = State(initialValue: preselectedAccountId ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Movimiento") {
                    Picker("Cuenta", selection: $selectedAccountId) {
                        ForEach(store.accounts) { account in
                            Text(account.name).tag(account.id ?? "")
                        }
                    }
                    Picker("Tipo", selection: $kind) {
                        Text("Cargo").tag("cargo")
                        Text("Abono").tag("abono")
                    }
                    .pickerStyle(.segmented)
                    TextField("Monto", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("Nota (opcional)", text: $note)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Registrar gasto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .task {
                if selectedAccountId.isEmpty {
                    selectedAccountId = store.accounts.first?.id ?? ""
                }
            }
            .sensoryFeedback(.success, trigger: savedTrigger)
        }
    }

    private func save() async {
        let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard !selectedAccountId.isEmpty, amount > 0 else {
            errorMessage = "Elige una cuenta y un monto mayor a cero"
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.addMovement(
                accountId: selectedAccountId,
                type: kind,
                amount: amount,
                note: note.trimmingCharacters(in: .whitespaces)
            )
            savedTrigger += 1
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar el movimiento"
        }
    }
}
