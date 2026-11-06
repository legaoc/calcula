import SwiftUI
import UniformTypeIdentifiers

// MARK: - Metas de ahorro (MAP.md §1.5 y §4.7)
//
// Lista de metas, detalle con anillo de progreso, formulario de alta y
// edición, "Apartar" y compartir. "Apartar" solo suma al campo `saved`
// (igual que la web: no crea movimiento ni mueve dinero de ninguna cuenta).

struct GoalsView: View {
    @EnvironmentObject private var store: DataStore

    @State private var showingNewGoal = false
    @State private var editingGoal: Goal?
    @State private var addingToGoal: Goal?
    @State private var deletingGoal: Goal?
    @State private var sharingGoal: Goal?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.goals.isEmpty {
                    ContentUnavailableView(
                        "Sin metas todavía",
                        systemImage: "target",
                        description: Text("Crea tu primera meta para empezar a apartar.")
                    )
                } else {
                    List {
                        ForEach(store.goals) { goal in
                            NavigationLink {
                                GoalDetailView(goal: goal)
                            } label: {
                                GoalRow(goal: goal)
                            }
                            .contextMenu {
                                Button("Editar") { editingGoal = goal }
                                Button("Apartar") { addingToGoal = goal }
                                Button("Compartir") { sharingGoal = goal }
                                Button("Eliminar", role: .destructive) {
                                    deletingGoal = goal
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.calculaBackground)
            .navigationTitle("Metas")
            .toolbar {
                Button {
                    showingNewGoal = true
                } label: {
                    Label("Nueva meta", systemImage: "plus")
                }
            }
            .sheet(isPresented: $showingNewGoal) {
                GoalFormView()
            }
            .sheet(item: $editingGoal) { goal in
                GoalFormView(goal: goal)
            }
            .sheet(item: $addingToGoal) { goal in
                AddToGoalView(goal: goal)
            }
            .sheet(item: $sharingGoal) { goal in
                GoalShareSheet(goal: goal)
            }
            .alert("Eliminar meta", isPresented: Binding(
                get: { deletingGoal != nil },
                set: { if !$0 { deletingGoal = nil } }
            )) {
                Button("Eliminar", role: .destructive) {
                    if let goal = deletingGoal {
                        Task { await deleteGoal(goal) }
                    }
                }
                Button("Cancelar", role: .cancel) { deletingGoal = nil }
            } message: {
                Text("Se eliminará «\(deletingGoal?.name ?? "")» y su avance guardado.")
            }
            .alert("Algo salió mal", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func deleteGoal(_ goal: Goal) async {
        do {
            try await store.deleteGoal(goal)
            deletingGoal = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Fila de meta

struct GoalRow: View {
    @EnvironmentObject private var store: DataStore

    let goal: Goal

    private var currency: String { store.profile?.currency ?? "MXN" }

    var body: some View {
        let status = FinanceCalc.goalStatus(goal: goal)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(goal.name)
                    .font(.headline)
                Spacer()
                Text("\(status.pct)%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("\(Format.money(goal.saved, currency: currency)) / \(Format.money(goal.target, currency: currency))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView(value: goal.progress)
                .tint(Color.calculaAccent)

            if status.left <= 0 {
                Text("¡Meta cumplida!")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Text("\(status.periods) \(periodUnitLabel(for: goal.cadence)) · \(Format.money(status.each, currency: currency)) c/u")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func periodUnitLabel(for cadence: String) -> String {
        switch cadence {
        case "daily": return "días"
        case "weekly": return "semanas"
        case "monthly": return "meses"
        default: return "quincenas" // fortnightly
        }
    }
}

// MARK: - Detalle de meta

/// Envoltorio para compartir un UIImage con ShareLink: UIImage no es
/// Transferable, así que se exporta como PNG.
private struct ShareableImage: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.image.pngData() ?? Data() }
    }
}

struct GoalDetailView: View {
    @EnvironmentObject private var store: DataStore

    let goal: Goal

    @State private var showingAdd = false
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var shareImage: UIImage?
    @State private var errorMessage: String?

    private var currency: String { store.profile?.currency ?? "MXN" }

    var body: some View {
        let status = FinanceCalc.goalStatus(goal: goal)
        ScrollView {
            VStack(spacing: 24) {
                // Hero: anillo con % + "Juntado $X de $Y" (como la web).
                HStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.25), lineWidth: 12)
                        Circle()
                            .trim(from: 0, to: goal.progress)
                            .stroke(Color.calculaAccent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(status.pct)%")
                            .font(.title.bold())
                    }
                    .frame(width: 120, height: 120)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Juntado")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(Format.money(goal.saved, currency: currency))
                            .font(.title2.bold())
                        Text("de \(Format.money(goal.target, currency: currency))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // Fichas: Resta / Cada quincena / Fecha (como la web).
                HStack(spacing: 8) {
                    goalFactBox(
                        label: "Resta",
                        value: Format.money(status.left, currency: currency)
                    )
                    goalFactBox(
                        label: "Cada \(cadenceLabel(for: goal.cadence))",
                        value: Format.money(status.each, currency: currency)
                    )
                    goalFactBox(
                        label: "Fecha",
                        value: goal.deadline.map { Format.shortDate($0) } ?? "Sin fecha"
                    )
                }

                // Botones: Compartir (principal) y Apartar / Editar.
                VStack(spacing: 12) {
                    if let image = shareImage {
                        ShareLink(
                            item: ShareableImage(image: image),
                            preview: SharePreview(goal.name, image: Image(uiImage: image))
                        ) {
                            Label("Compartir", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.calculaAccent)
                        .frame(maxWidth: .infinity)
                    } else {
                        ShareLink(item: shareText(status: status)) {
                            Label("Compartir", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.calculaAccent)
                        .frame(maxWidth: .infinity)
                    }

                    HStack(spacing: 12) {
                        Button("Apartar") { showingAdd = true }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        Button("Editar") { showingEdit = true }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }

                    Button("Eliminar meta", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                    .font(.subheadline)
                }
            }
            .padding()
        }
        .background(Color.calculaBackground)
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAdd) {
            AddToGoalView(goal: goal)
        }
        .sheet(isPresented: $showingEdit) {
            GoalFormView(goal: goal)
        }
        .confirmationDialog("Eliminar meta", isPresented: $showingDeleteConfirm) {
            Button("Eliminar", role: .destructive) {
                Task { await deleteGoal() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se eliminará «\(goal.name)» y su avance guardado.")
        }
        .alert("Algo salió mal", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            // Renderiza la tarjeta para compartir como imagen (como la web,
            // que dibuja un PNG 1080×1350 en canvas). Si falla, el botón
            // de compartir usa el texto.
            let renderer = ImageRenderer(content: GoalShareCard(goal: goal, currency: currency))
            renderer.scale = 2
            shareImage = renderer.uiImage
        }
    }

    /// Una ficha del detalle de meta (Resta / Cada quincena / Fecha),
    /// como las `.goal-facts` de la web.
    private func goalFactBox(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.calculaCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func cadenceLabel(for cadence: String) -> String {
        switch cadence {
        case "daily": return "día"
        case "weekly": return "semana"
        case "fortnightly": return "quincena"
        case "monthly": return "mes"
        default: return "quincena"
        }
    }

    private func shareText(status: (left: Double, periods: Int, each: Double, pct: Int)) -> String {
        "¡Estoy ahorrando para \(goal.name)! Llevo \(Format.money(goal.saved, currency: currency)) de \(Format.money(goal.target, currency: currency)) (\(status.pct)%). — Calcula"
    }

    private func deleteGoal() async {
        do {
            try await store.deleteGoal(goal)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Tarjeta para compartir (se renderiza a imagen con ImageRenderer)

private struct GoalShareCard: View {
    let goal: Goal
    let currency: String

    var body: some View {
        let status = FinanceCalc.goalStatus(goal: goal)
        VStack(spacing: 20) {
            Text("Calcula")
                .font(.caption.weight(.bold))
                .tracking(4)
                .foregroundStyle(.secondary)
            Text(goal.name)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: goal.progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(status.pct)%")
                    .font(.title2.bold())
            }
            .frame(width: 110, height: 110)
            Text("\(Format.money(goal.saved, currency: currency)) de \(Format.money(goal.target, currency: currency))")
                .font(.headline)
            if status.left > 0 {
                Text("Faltan \(Format.money(status.left, currency: currency)) · \(Format.money(status.each, currency: currency)) cada \(cadenceWord)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("¡Meta cumplida!")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(36)
        .frame(width: 360)
        .background(Color(red: 0.067, green: 0.067, blue: 0.07))
        .foregroundStyle(.white)
    }

    private var cadenceWord: String {
        switch goal.cadence {
        case "weekly": return "semana"
        case "monthly": return "mes"
        default: return "quincena"
        }
    }
}

// MARK: - Hoja para compartir desde el menú (texto)

private struct GoalShareSheet: View {
    let goal: Goal

    @EnvironmentObject private var store: DataStore

    var body: some View {
        let status = FinanceCalc.goalStatus(goal: goal)
        let currency = store.profile?.currency ?? "MXN"
        NavigationStack {
            VStack(spacing: 20) {
                Text(goal.name)
                    .font(.title2.bold())
                Text("Llevo \(Format.money(goal.saved, currency: currency)) de \(Format.money(goal.target, currency: currency)) (\(status.pct)%).")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                ShareLink(
                    item: "¡Estoy ahorrando para \(goal.name)! Llevo \(Format.money(goal.saved, currency: currency)) de \(Format.money(goal.target, currency: currency)) (\(status.pct)%). — Calcula"
                ) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.calculaAccent)
            }
            .padding()
            .navigationTitle("Compartir meta")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Apartar a una meta

private struct AddToGoalView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let goal: Goal

    @State private var amount: Double = 0
    @State private var errorMessage: String?

    private var currency: String { store.profile?.currency ?? "MXN" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Apartar a «\(goal.name)»")
                        .font(.headline)
                    Text("Llevas \(Format.money(goal.saved, currency: currency)) de \(Format.money(goal.target, currency: currency)).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Monto") {
                    TextField("0.00", value: $amount, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Apartar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apartar") {
                        Task { await save() }
                    }
                    .disabled(amount <= 0)
                }
            }
            .alert("Algo salió mal", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() async {
        do {
            try await store.addToGoal(goal, amount: amount)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Formulario de alta / edición de meta

struct GoalFormView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    /// nil = crear; con valor = editar (prellenado).
    private let existingGoal: Goal?

    @State private var name: String
    @State private var target: Double
    @State private var cadence: String
    @State private var deadline: Date
    @State private var errorMessage: String?

    init(goal: Goal? = nil) {
        self.existingGoal = goal
        _name = State(initialValue: goal?.name ?? "")
        _target = State(initialValue: goal?.target ?? 0)
        _cadence = State(initialValue: goal?.cadence ?? "fortnightly")
        _deadline = State(initialValue: goal?.deadline
            ?? Calendar.current.date(byAdding: .month, value: 3, to: Date())!)
    }

    private var isEditing: Bool { existingGoal != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meta") {
                    TextField("Nombre", text: $name)
                    TextField("Objetivo", value: $target, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                }

                Section("Aportaciones") {
                    Picker("Frecuencia", selection: $cadence) {
                        Text("Cada semana").tag("weekly")
                        Text("Cada quincena").tag("fortnightly")
                        Text("Cada mes").tag("monthly")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Fecha objetivo") {
                    // Al crear, la fecha debe ser futura (como la web).
                    // Al editar, la web no valida, así que se permite
                    // cualquier fecha.
                    if isEditing {
                        DatePicker("Fecha", selection: $deadline, displayedComponents: .date)
                    } else {
                        DatePicker(
                            "Fecha",
                            selection: $deadline,
                            in: Calendar.current.startOfDay(for: Date())...,
                            displayedComponents: .date
                        )
                    }
                }
            }
            .navigationTitle(isEditing ? "Editar meta" : "Nueva meta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Guardar" : "Crear") {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || target <= 0)
                }
            }
            .alert("Algo salió mal", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() async {
        do {
            if var goal = existingGoal {
                goal.name = name.trimmingCharacters(in: .whitespaces)
                goal.target = target
                goal.cadence = cadence
                goal.deadline = deadline
                try await store.updateGoal(goal)
            } else {
                try await store.addGoal(
                    name: name.trimmingCharacters(in: .whitespaces),
                    target: target,
                    cadence: cadence,
                    deadline: deadline
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
