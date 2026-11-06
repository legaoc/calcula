import Foundation
import FirebaseFirestore

/// Capa de datos Firestore (mismo modelo que la web).
/// Rutas: users/{uid}/accounts, users/{uid}/movements, etc.
/// A diferencia de la versión web, aquí SÍ se usa la persistencia local
/// del SDK nativo: en iOS funciona bien y da datos sin conexión.
@MainActor
final class DataStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var movements: [Movement] = []
    @Published private(set) var accountMovements: [Movement] = []
    @Published private(set) var goals: [Goal] = []
    @Published private(set) var budgets: [Budget] = []
    @Published private(set) var scheduledPayments: [ScheduledPayment] = []
    @Published private(set) var payroll = PayrollSettings()
    @Published private(set) var reminderSettings = ReminderSettings()
    @Published private(set) var financeMovements: [Movement] = []
    @Published private(set) var profile: UserProfile?
    @Published private(set) var profileLoaded = false
    @Published private(set) var isListening = false
    @Published private(set) var lastError: String?
    @Published private(set) var cloudSyncEnabled = true
    @Published private(set) var syncInSync = false

    private let db = Firestore.firestore()
    private var accountsListener: ListenerRegistration?
    private var movementsListener: ListenerRegistration?
    private var accountMovementsListener: ListenerRegistration?
    private var goalsListener: ListenerRegistration?
    private var budgetsListener: ListenerRegistration?
    private var schedulesListener: ListenerRegistration?
    private var payrollListener: ListenerRegistration?
    private var remindersListener: ListenerRegistration?
    private var financeListener: ListenerRegistration?
    private var profileListener: ListenerRegistration?
    private var syncDeregister: (() -> Void)?
    private var uid: String?

    /// Total pendiente del inicio (igual que la web): suma de max(0, balance)
    /// solo de cuentas type "charges" (las recurrentes siempre tienen 0).
    var totalBalance: Double {
        accounts.filter { $0.type == "charges" }
            .map { max(0, $0.balance) }
            .reduce(0, +)
    }

    var visibleAccounts: [Account] {
        accounts.filter { !$0.hiddenFromHome }
    }

    func startListening(uid: String) {
        stopListening()
        self.uid = uid
        isListening = true
        lastError = nil

        accountsListener = userCollection(uid, "accounts")
            .order(by: "sortOrder")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error {
                        self?.lastError = error.localizedDescription
                        return
                    }
                    self?.accounts = snapshot?.documents.compactMap {
                        try? $0.data(as: Account.self)
                    } ?? []
                }
            }

        movementsListener = userCollection(uid, "movements")
            .order(by: "createdAt", descending: true)
            .limit(to: 40)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error {
                        self?.lastError = error.localizedDescription
                        return
                    }
                    self?.movements = snapshot?.documents.compactMap {
                        try? $0.data(as: Movement.self)
                    } ?? []
                }
            }

        profileListener = db.collection("users").document(uid)
            .collection("settings").document("profile")
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    self?.profile = try? snapshot?.data(as: UserProfile.self)
                    self?.profileLoaded = true
                }
            }

        goalsListener = userCollection(uid, "goals")
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    self?.goals = snapshot?.documents.compactMap {
                        try? $0.data(as: Goal.self)
                    } ?? []
                }
            }

        budgetsListener = userCollection(uid, "budgets")
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    self?.budgets = snapshot?.documents.compactMap {
                        try? $0.data(as: Budget.self)
                    } ?? []
                }
            }

        schedulesListener = userCollection(uid, "scheduledPayments")
            .whereField("active", isEqualTo: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    let items = snapshot?.documents.compactMap {
                        try? $0.data(as: ScheduledPayment.self)
                    } ?? []
                    // Sin orderBy en Firestore (como la web): orden en
                    // cliente por nextPayment asc (sin fecha al final).
                    self?.scheduledPayments = items.sorted {
                        ($0.nextPayment ?? .distantFuture) < ($1.nextPayment ?? .distantFuture)
                    }
                }
            }

        payrollListener = db.collection("users").document(uid)
            .collection("settings").document("payroll")
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    if let settings = try? snapshot?.data(as: PayrollSettings.self) {
                        self?.payroll = settings
                    }
                }
            }

        remindersListener = db.collection("users").document(uid)
            .collection("settings").document("reminders")
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    if let settings = try? snapshot?.data(as: ReminderSettings.self) {
                        self?.reminderSettings = settings
                    }
                }
            }

        // Todos los movimientos (sin límite), como subscribeBalanceSync
        // de la web: es la fuente de Finanzas y presupuestos.
        financeListener = userCollection(uid, "movements")
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    self?.financeMovements = snapshot?.documents.compactMap {
                        try? $0.data(as: Movement.self)
                    } ?? []
                }
            }

        // Estado de sincronización (onSnapshotsInSync de la web).
        syncInSync = false
        syncDeregister = db.addSnapshotsInSyncListener { [weak self] in
            Task { @MainActor in
                self?.syncInSync = true
            }
        }

        applyStoredCloudSyncPreference()
    }

    func stopListening() {
        accountsListener?.remove()
        movementsListener?.remove()
        accountMovementsListener?.remove()
        goalsListener?.remove()
        budgetsListener?.remove()
        schedulesListener?.remove()
        payrollListener?.remove()
        remindersListener?.remove()
        financeListener?.remove()
        profileListener?.remove()
        syncDeregister?()
        accountsListener = nil
        movementsListener = nil
        accountMovementsListener = nil
        goalsListener = nil
        budgetsListener = nil
        schedulesListener = nil
        payrollListener = nil
        remindersListener = nil
        financeListener = nil
        profileListener = nil
        syncDeregister = nil
        uid = nil
        isListening = false
        syncInSync = false
        accounts = []
        movements = []
        accountMovements = []
        goals = []
        budgets = []
        scheduledPayments = []
        financeMovements = []
        profile = nil
        profileLoaded = false
    }

    /// Movimientos de una cuenta (suscripción propia, como la web):
    /// sin orderBy en Firestore, orden en cliente por createdAt desc.
    func startAccountMovements(accountId: String) {
        guard let uid else { return }
        stopAccountMovements()
        accountMovementsListener = userCollection(uid, "movements")
            .whereField("accountId", isEqualTo: accountId)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    let items = snapshot?.documents.compactMap {
                        try? $0.data(as: Movement.self)
                    } ?? []
                    self?.accountMovements = items.sorted {
                        ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
                    }
                }
            }
    }

    func stopAccountMovements() {
        accountMovementsListener?.remove()
        accountMovementsListener = nil
        accountMovements = []
    }

    // MARK: - Cuentas

    func addAccount(
        name: String,
        type: String,
        isSubscription: Bool,
        initialBalance: Double,
        dueDay: Int,
        categories: [String]
    ) async throws {
        guard let uid else { return }
        let account = Account(
            name: name,
            type: type,
            isSubscription: isSubscription,
            balance: initialBalance,
            dueDay: dueDay,
            categories: categories,
            sortOrder: nextSortOrder()
        )
        try await userCollection(uid, "accounts").addDocument(from: account)
    }

    /// Borra la cuenta y, como la web, todos sus movimientos y pagos
    /// programados (en lotes de 450, el límite de Firestore es 500).
    func deleteAccount(_ account: Account) async throws {
        guard let uid, let id = account.id else { return }
        let movements = try await userCollection(uid, "movements")
            .whereField("accountId", isEqualTo: id)
            .getDocuments().documents
        let payments = try await userCollection(uid, "scheduledPayments")
            .whereField("accountId", isEqualTo: id)
            .getDocuments().documents
        var refs = (movements + payments).map(\.reference)
        refs.append(userCollection(uid, "accounts").document(id))
        for chunk in refs.chunked(into: 450) {
            let batch = db.batch()
            chunk.forEach { batch.deleteDocument($0) }
            try await batch.commit()
        }
    }

    func setAccountHidden(_ account: Account, hidden: Bool) async throws {
        guard let uid, let id = account.id else { return }
        try await userCollection(uid, "accounts").document(id)
            .updateData(["hiddenFromHome": hidden])
    }

    func setAccountColor(_ account: Account, hex: String) async throws {
        guard let uid, let id = account.id else { return }
        try await userCollection(uid, "accounts").document(id)
            .updateData(["cardColor": hex])
    }

    /// Reordena las tarjetas (persiste `sortOrder` por cuenta).
    func reorderAccounts(_ ordered: [Account]) async throws {
        guard let uid else { return }
        for (index, account) in ordered.enumerated() {
            guard let id = account.id else { continue }
            try await userCollection(uid, "accounts").document(id)
                .updateData(["sortOrder": index])
        }
    }

    /// Guarda el perfil (setDoc con merge).
    func saveProfile(_ profile: UserProfile) async throws {
        guard let uid else { return }
        try await db.collection("users").document(uid)
            .collection("settings").document("profile")
            .setData(from: profile, merge: true)
    }

    /// "Sincronizar ahora": fuerza una lectura a Firestore para comprobar
    /// la conexión y registra cuándo se sincronizó por última vez.
    @Published private(set) var lastSyncAt: Date?

    func syncNow() async {
        guard let uid else { return }
        syncInSync = false
        _ = try? await db.collection("users").document(uid)
            .collection("settings").document("profile").getDocument()
        lastSyncAt = Date()
        syncInSync = true
    }

    // MARK: - Movimientos

    /// Igual que la web: crea el movimiento y ajusta el saldo de la cuenta
    /// (cargo suma, abono resta; "pago" no mueve saldos).
    func addMovement(accountId: String, type: String, amount: Double, note: String) async throws {
        guard let uid else { return }
        let movement = Movement(accountId: accountId, type: type, amount: amount, note: note)
        try await userCollection(uid, "movements").addDocument(from: movement)
        if movement.balanceDelta != 0 {
            try await applyBalanceDelta(accountId: accountId, delta: movement.balanceDelta)
        }
    }

    /// Borra el movimiento y revierte su efecto en el saldo
    /// (solo cargo/abono; borrar un "pago" no toca saldos).
    func deleteMovement(_ movement: Movement) async throws {
        guard let uid, let id = movement.id else { return }
        try await userCollection(uid, "movements").document(id).delete()
        if movement.balanceDelta != 0 {
            try await applyBalanceDelta(accountId: movement.accountId, delta: -movement.balanceDelta)
        }
    }

    // MARK: - Metas

    func addGoal(name: String, target: Double, cadence: String, deadline: Date) async throws {
        guard let uid else { return }
        let goal = Goal(name: name, target: target, saved: 0, cadence: cadence, deadline: deadline)
        try await userCollection(uid, "goals").addDocument(from: goal)
    }

    func updateGoal(_ goal: Goal) async throws {
        guard let uid, let id = goal.id else { return }
        var data: [String: Any] = [
            "name": goal.name,
            "target": goal.target,
            "cadence": goal.cadence,
        ]
        if let deadline = goal.deadline {
            data["deadline"] = deadline
        }
        try await userCollection(uid, "goals").document(id).updateData(data)
    }

    func deleteGoal(_ goal: Goal) async throws {
        guard let uid, let id = goal.id else { return }
        try await userCollection(uid, "goals").document(id).delete()
    }

    /// "Apartar": solo suma al campo `saved` (igual que la web: no crea
    /// movimiento ni mueve dinero de ninguna cuenta).
    func addToGoal(_ goal: Goal, amount: Double) async throws {
        guard let uid, let id = goal.id else { return }
        try await userCollection(uid, "goals").document(id)
            .updateData(["saved": goal.saved + amount])
    }

    // MARK: - Presupuestos

    func addBudget(name: String, amount: Double, category: String) async throws {
        guard let uid else { return }
        let budget = Budget(name: name, amount: amount, category: category)
        try await userCollection(uid, "budgets").addDocument(from: budget)
    }

    func deleteBudget(_ budget: Budget) async throws {
        guard let uid, let id = budget.id else { return }
        try await userCollection(uid, "budgets").document(id).delete()
    }

    // MARK: - Pagos programados

    func addScheduledPayment(_ payment: ScheduledPayment) async throws {
        guard let uid else { return }
        try await userCollection(uid, "scheduledPayments").addDocument(from: payment)
    }

    func updateScheduledPayment(id: String, patch: [String: Any]) async throws {
        guard let uid else { return }
        try await userCollection(uid, "scheduledPayments").document(id).updateData(patch)
    }

    /// Pagar un recurrente (igual que la web): crea un movimiento
    /// type "pago" (no mueve saldos) y avanza `nextPayment` según la
    /// frecuencia.
    func payScheduled(_ payment: ScheduledPayment) async throws {
        guard let uid, let id = payment.id,
              let next = payment.nextPayment else { return }
        let movement = Movement(
            accountId: payment.accountId,
            type: "pago",
            amount: payment.amount,
            note: "Pago: \(payment.name)",
            scheduledPaymentId: id
        )
        try await userCollection(uid, "movements").addDocument(from: movement)
        let following = QuincenaEngine.nextOccurrence(
            next, frequency: payment.frequency, customDays: payment.customDays
        )
        try await userCollection(uid, "scheduledPayments").document(id)
            .updateData(["nextPayment": following])
    }

    // MARK: - Nómina y recordatorios

    /// setDoc sin merge (igual que la web).
    func setPayroll(_ settings: PayrollSettings) async throws {
        guard let uid else { return }
        try await db.collection("users").document(uid)
            .collection("settings").document("payroll")
            .setData(from: settings)
    }

    /// setDoc con merge (igual que la web).
    func setReminderSettings(_ settings: ReminderSettings) async throws {
        guard let uid else { return }
        try await db.collection("users").document(uid)
            .collection("settings").document("reminders")
            .setData(from: settings, merge: true)
    }

    // MARK: - Sincronización con la nube

    /// Misma clave que la web (`calcula-cloud-sync`): "0" = nube apagada.
    private var storedCloudSyncEnabled: Bool {
        UserDefaults.standard.string(forKey: "calcula-cloud-sync") != "0"
    }

    private func applyStoredCloudSyncPreference() {
        setCloudSync(enabled: storedCloudSyncEnabled)
    }

    func setCloudSync(enabled: Bool) {
        cloudSyncEnabled = enabled
        UserDefaults.standard.set(enabled ? "1" : "0", forKey: "calcula-cloud-sync")
        syncInSync = false
        if enabled {
            db.enableNetwork { _ in }
        } else {
            db.disableNetwork { _ in }
        }
    }

    // MARK: - Onboarding

    /// Guarda el perfil del onboarding y crea las cuentas "Gastos" y
    /// "Ahorro" según lo elegido (igual que `finishOnboarding` en la web).
    func finishOnboarding(
        name: String,
        income: String,
        currency: String,
        colors: [String],
        wants: [String]
    ) async throws {
        guard let uid else { return }
        try await db.collection("users").document(uid)
            .collection("settings").document("profile")
            .setData([
                "name": name,
                "income": income,
                "currency": currency,
                "colors": colors,
                "wants": wants,
                "onboardingDone": true,
            ], merge: true)
        let color = colors.first ?? "111111"
        let color2 = colors.dropFirst().first ?? color
        if wants.contains("charges"), !accounts.contains(where: { $0.name == "Gastos" }) {
            var account = Account(name: "Gastos", type: "charges", balance: 0)
            account.cardColor = color
            account.sortOrder = nextSortOrder()
            try await userCollection(uid, "accounts").addDocument(from: account)
        }
        if wants.contains("savings"), !accounts.contains(where: { $0.name == "Ahorro" }) {
            var account = Account(name: "Ahorro", type: "charges", balance: 0)
            account.cardColor = color2
            account.sortOrder = nextSortOrder()
            try await userCollection(uid, "accounts").addDocument(from: account)
        }
    }

    // MARK: - Privado

    private func userCollection(_ uid: String, _ name: String) -> CollectionReference {
        db.collection("users").document(uid).collection(name)
    }

    private func nextSortOrder() -> Int {
        (accounts.map(\.sortOrder).max() ?? 0) + 1
    }

    private func applyBalanceDelta(accountId: String, delta: Double) async throws {
        guard let uid else { return }
        guard let account = accounts.first(where: { $0.id == accountId }) else { return }
        try await userCollection(uid, "accounts").document(accountId)
            .updateData(["balance": account.balance + delta])
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
