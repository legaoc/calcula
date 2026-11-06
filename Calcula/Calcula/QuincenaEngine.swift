import Foundation

// MARK: - Motor de quincenas (port fiel de la web: MAP.md §4.2–4.5)
// Una "quincena" es el periodo que empieza en un día de pago (nómina) y
// termina en el siguiente. El plan reparte cada pago recurrente en partes
// iguales entre las últimas N quincenas antes de su vencimiento.

struct QuincenaWindow: Equatable {
    /// Inicio = día de pago. Fin = siguiente día de pago (excluido).
    var start: Date
    var end: Date
}

struct QuincenaContext {
    var windows: [QuincenaWindow]
    var currentIndex: Int

    var current: QuincenaWindow { windows[currentIndex] }
    var next: QuincenaWindow? {
        windows.indices.contains(currentIndex + 1) ? windows[currentIndex + 1] : nil
    }
}

enum QuincenaKind: String {
    case recurring
    case charges
}

struct QuincenaItem: Identifiable {
    var id: String
    var payment: ScheduledPayment
    var account: Account
    var amount: Double
    /// Parte que toca en esta quincena.
    var share: Double
    var isDue: Bool
    var overdue: Bool
    var due: Date
    /// Entre cuántas quincenas se reparte.
    var split: Int
    /// Qué parte es esta (1...split).
    var installment: Int
    var count: Int
    var dueCount: Int
    var unitAmount: Double
    var occurrenceIndex: Int
    var occurrenceTotal: Int
    var kind: QuincenaKind
}

struct QuincenaPlan {
    var window: QuincenaWindow
    var items: [QuincenaItem]
    var fromPayroll: Double
    var toPay: Double
    var toSetAside: Double
}

enum QuincenaEngine {
    static let calendar = Calendar.current

    // MARK: - Fechas base

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func lastDayOfMonth(year: Int, month: Int) -> Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        guard let date = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: date)
        else { return 30 }
        return range.count
    }

    /// Suma meses conservando el día, limitado al último día del mes destino
    /// (igual que el JS: setDate(1) → setMonth → setDate(min(day, last))).
    static func addingMonths(_ date: Date, _ months: Int) -> Date {
        let day = calendar.component(.day, from: date)
        var base = calendar.date(
            from: DateComponents(
                year: calendar.component(.year, from: date),
                month: calendar.component(.month, from: date),
                day: 1
            )
        )!
        base = calendar.date(byAdding: .month, value: months, to: base)!
        let last = lastDayOfMonth(
            year: calendar.component(.year, from: base),
            month: calendar.component(.month, from: base)
        )
        return calendar.date(
            from: DateComponents(
                year: calendar.component(.year, from: base),
                month: calendar.component(.month, from: base),
                day: min(day, last)
            )
        )!
    }

    // MARK: - Nómina / ventanas

    static func makePayday(year: Int, month: Int, which: Int, settings: PayrollSettings) -> Date {
        let last = lastDayOfMonth(year: year, month: month)
        if which == 1 {
            return calendar.date(
                from: DateComponents(year: year, month: month, day: min(settings.payday1, last))
            )!
        }
        if settings.payday2LastDay {
            return calendar.date(from: DateComponents(year: year, month: month, day: last))!
        }
        return calendar.date(
            from: DateComponents(year: year, month: month, day: min(settings.payday2, last))
        )!
    }

    /// Días de pago de 15 meses (de -4 a +10 respecto al mes actual),
    /// ordenados, sin duplicados; ventanas [payday_i, payday_{i+1}).
    static func quincenaWindows(now: Date = Date(), settings: PayrollSettings) -> [QuincenaWindow] {
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        var paydays: [Date] = []
        for i in -4...10 {
            let cursor = calendar.date(
                from: DateComponents(year: year, month: month + i, day: 1)
            )!
            let y = calendar.component(.year, from: cursor)
            let m = calendar.component(.month, from: cursor)
            paydays.append(makePayday(year: y, month: m, which: 1, settings: settings))
            paydays.append(makePayday(year: y, month: m, which: 2, settings: settings))
        }
        paydays.sort()
        var unique: [Date] = []
        for date in paydays where unique.last != date {
            unique.append(date)
        }
        var windows: [QuincenaWindow] = []
        for i in 0..<(unique.count - 1) {
            windows.append(QuincenaWindow(start: unique[i], end: unique[i + 1]))
        }
        return windows
    }

    static func windowContains(_ window: QuincenaWindow, _ date: Date) -> Bool {
        let day = startOfDay(date)
        return day >= window.start && day < window.end
    }

    static func findWindowIndex(_ windows: [QuincenaWindow], _ date: Date) -> Int {
        windows.firstIndex { windowContains($0, date) } ?? -1
    }

    static func currentAndNext(now: Date = Date(), settings: PayrollSettings) -> QuincenaContext {
        let today = startOfDay(now)
        let windows = quincenaWindows(now: now, settings: settings)
        var currentIndex = windows.firstIndex { windowContains($0, today) } ?? -1
        if currentIndex < 0 {
            currentIndex = windows.firstIndex { today < $0.end } ?? -1
        }
        let safeIndex = currentIndex < 0 ? max(0, windows.count - 1) : currentIndex
        return QuincenaContext(windows: windows, currentIndex: safeIndex)
    }

    // MARK: - Frecuencias y ocurrencias

    enum Frequency {
        case days(Int)
        case months(Int)
        case custom
    }

    static func frequencyConfig(_ key: String) -> Frequency {
        switch key {
        case "weekly": return .days(7)
        case "every15": return .days(15)
        case "monthly": return .months(1)
        case "bimonthly": return .months(2)
        case "quarterly": return .months(3)
        case "semiannual": return .months(6)
        case "annual": return .months(12)
        case "custom": return .custom
        default: return .days(7)
        }
    }

    static func frequencyLabel(_ key: String) -> String {
        switch key {
        case "weekly": return "Cada semana"
        case "every15": return "Cada 15 días"
        case "monthly": return "Cada mes"
        case "bimonthly": return "Cada 2 meses"
        case "quarterly": return "Cada 3 meses"
        case "semiannual": return "Cada 6 meses"
        case "annual": return "Cada año"
        case "custom": return "Personalizado"
        default: return "Cada semana"
        }
    }

    static func nextOccurrence(_ date: Date, frequency: String, customDays: Int = 30) -> Date {
        switch frequencyConfig(frequency) {
        case .days(let interval):
            return calendar.date(byAdding: .day, value: interval, to: date)!
        case .months(let interval):
            return addingMonths(date, interval)
        case .custom:
            return calendar.date(byAdding: .day, value: max(1, customDays), to: date)!
        }
    }

    static func prevOccurrence(_ date: Date, frequency: String, customDays: Int = 30) -> Date {
        switch frequencyConfig(frequency) {
        case .days(let interval):
            return calendar.date(byAdding: .day, value: -interval, to: date)!
        case .months(let interval):
            return addingMonths(date, -interval)
        case .custom:
            return calendar.date(byAdding: .day, value: -max(1, customDays), to: date)!
        }
    }

    /// Ocurrencias desde nextPayment hasta `until` (máx. 24), a mediodía.
    static func occurrenceDates(_ payment: ScheduledPayment, until: Date) -> [Date] {
        guard var current = payment.nextPayment else { return [] }
        var dates: [Date] = []
        var guardCount = 0
        while current <= until && guardCount < 24 {
            let comps = calendar.dateComponents([.year, .month, .day], from: current)
            dates.append(calendar.date(
                from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 12)
            )!)
            current = nextOccurrence(current, frequency: payment.frequency, customDays: payment.customDays)
            guardCount += 1
        }
        return dates
    }

    /// Ocurrencias en un rango, buscando también hacia atrás (máx. 40 pasos
    /// en cada dirección). Para el calendario.
    static func occurrencesInRange(_ payment: ScheduledPayment, from: Date, until: Date) -> [Date] {
        guard let first = payment.nextPayment else { return [] }
        var dates: [Date] = []
        var back = first
        var backCount = 0
        while back > from && backCount < 40 {
            back = prevOccurrence(back, frequency: payment.frequency, customDays: payment.customDays)
            backCount += 1
            if back >= from && back <= until { dates.append(back) }
        }
        var fwd = first
        var fwdCount = 0
        while fwd <= until && fwdCount < 40 {
            if fwd >= from { dates.append(fwd) }
            fwd = nextOccurrence(fwd, frequency: payment.frequency, customDays: payment.customDays)
            fwdCount += 1
        }
        return dates.sorted()
    }

    /// Nº de quincenas entre las que se reparte (1–12). La web lee
    /// `splitParts || splitQuincenas`; aquí se usa ese mismo fallback para
    /// que los planes del studio (semanas/meses) también repartan.
    static func getSplitCount(_ payment: ScheduledPayment) -> Int {
        let raw = payment.splitParts ?? payment.splitQuincenas ?? 1
        return min(12, max(1, raw))
    }

    // MARK: - Vencimiento de cuentas de cargos

    static func upcomingChargeDue(dueDay: Int, fromDate: Date) -> Date? {
        let day = dueDay
        guard day >= 1 else { return nil }
        let start = startOfDay(fromDate)
        for i in 0..<62 {
            guard let cursor = calendar.date(byAdding: .day, value: i, to: start) else { continue }
            let last = lastDayOfMonth(
                year: calendar.component(.year, from: cursor),
                month: calendar.component(.month, from: cursor)
            )
            if calendar.component(.day, from: cursor) == min(day, last) {
                return cursor
            }
        }
        return nil
    }

    static func lastChargeDue(dueDay: Int, fromDate: Date) -> Date? {
        let day = dueDay
        guard day >= 1 else { return nil }
        let start = startOfDay(fromDate)
        for i in 1...62 {
            guard let cursor = calendar.date(byAdding: .day, value: -i, to: start) else { continue }
            let last = lastDayOfMonth(
                year: calendar.component(.year, from: cursor),
                month: calendar.component(.month, from: cursor)
            )
            if calendar.component(.day, from: cursor) == min(day, last) {
                return cursor
            }
        }
        return nil
    }

    static func resolveChargeDue(
        _ account: Account, context: QuincenaContext
    ) -> (due: Date, overdue: Bool, targetWindowIndex: Int)? {
        let dueDay = account.dueDay
        guard dueDay >= 1 else { return nil }
        let today = startOfDay(Date())
        if let last = lastChargeDue(dueDay: dueDay, fromDate: today),
           windowContains(context.current, last) {
            return (due: last, overdue: true, targetWindowIndex: context.currentIndex)
        }
        guard let upcoming = upcomingChargeDue(dueDay: dueDay, fromDate: today) else { return nil }
        let index = findWindowIndex(context.windows, upcoming)
        guard index >= 0 else { return nil }
        return (due: upcoming, overdue: false, targetWindowIndex: index)
    }

    // MARK: - Plan de quincena (el cálculo central)

    static func buildQuincenaPlan(
        windowIndex: Int,
        context: QuincenaContext,
        payments: [ScheduledPayment],
        accounts: [Account]
    ) -> QuincenaPlan {
        let window = context.windows[windowIndex]
        let today = startOfDay(Date())
        var grouped: [String: QuincenaItem] = [:]
        var order: [String] = []

        func upsert(_ key: String, _ item: QuincenaItem) {
            if grouped[key] == nil { order.append(key) }
            grouped[key] = item
        }

        for payment in payments {
            guard let account = accounts.first(where: { $0.id == payment.accountId }) else { continue }
            let amount = payment.amount
            guard amount > 0 else { continue }
            let split = getSplitCount(payment)
            let dates = occurrenceDates(payment, until: context.windows.last!.end)
            for due in dates {
                let dueIndex = findWindowIndex(context.windows, due)
                guard dueIndex >= 0 else { continue }
                let overdue = startOfDay(due) < today
                let isDueHere = windowContains(window, due)
                    || (overdue && windowIndex == context.currentIndex)
                if overdue && windowIndex != context.currentIndex { continue }

                let contributing: [Int]
                if overdue {
                    contributing = [context.currentIndex]
                } else {
                    let startIndex = max(context.currentIndex, dueIndex - (split - 1))
                    contributing = Array(startIndex...dueIndex)
                }
                guard contributing.contains(windowIndex) else { continue }
                let share = amount / Double(contributing.count)
                let key = isDueHere
                    ? "\(payment.id ?? ""):\(startOfDay(due).timeIntervalSince1970)"
                    : (payment.id ?? "")

                var item = grouped[key] ?? QuincenaItem(
                    id: key,
                    payment: payment,
                    account: account,
                    amount: 0,
                    share: 0,
                    isDue: false,
                    overdue: false,
                    due: due,
                    split: contributing.count,
                    installment: (contributing.firstIndex(of: windowIndex) ?? 0) + 1,
                    count: 0,
                    dueCount: 0,
                    unitAmount: amount,
                    occurrenceIndex: 1,
                    occurrenceTotal: 1,
                    kind: .recurring
                )
                item.share += share
                item.count += 1
                item.unitAmount = amount
                item.split = contributing.count
                item.installment = (contributing.firstIndex(of: windowIndex) ?? 0) + 1
                if isDueHere {
                    item.isDue = true
                    item.amount += amount
                    item.dueCount += 1
                    item.due = due
                    if overdue { item.overdue = true }
                } else if !item.isDue {
                    item.due = due
                    item.amount = amount
                }
                upsert(key, item)
            }
        }

        for account in accounts where account.type == "charges" {
            let balance = account.balance
            guard balance > 0 else { continue }
            guard let resolved = resolveChargeDue(account, context: context) else { continue }
            guard resolved.targetWindowIndex == windowIndex else { continue }
            let fakePayment = ScheduledPayment(
                id: "charge-\(account.id ?? "")",
                accountId: account.id ?? "",
                name: account.name,
                amount: balance
            )
            let item = QuincenaItem(
                id: "charge:\(account.id ?? "")",
                payment: fakePayment,
                account: account,
                amount: balance,
                share: balance,
                isDue: true,
                overdue: resolved.overdue,
                due: resolved.due,
                split: 1,
                installment: 1,
                count: 1,
                dueCount: 1,
                unitAmount: balance,
                occurrenceIndex: 1,
                occurrenceTotal: 1,
                kind: .charges
            )
            upsert(item.id, item)
        }

        var items = order.compactMap { grouped[$0] }

        // occurrenceIndex / occurrenceTotal por pago (solo isDue, recurrentes).
        var dueByPayment: [String: [QuincenaItem]] = [:]
        for item in items where item.isDue && item.kind == .recurring {
            dueByPayment[item.payment.id ?? "", default: []].append(item)
        }
        for list in dueByPayment.values {
            let sorted = list.sorted { startOfDay($0.due) < startOfDay($1.due) }
            for (index, item) in sorted.enumerated() {
                if let i = items.firstIndex(where: { $0.id == item.id }) {
                    items[i].occurrenceIndex = index + 1
                    items[i].occurrenceTotal = sorted.count
                    items[i].dueCount = 1
                }
            }
        }

        items.sort {
            if $0.isDue != $1.isDue { return $0.isDue }
            return startOfDay($0.due) < startOfDay($1.due)
        }

        let toPay = items.filter(\.isDue).map(\.amount).reduce(0, +)
        let fromPayroll = items.map(\.share).reduce(0, +)
        let toSetAside = items.filter { !$0.isDue }.map(\.share).reduce(0, +)
        return QuincenaPlan(window: window, items: items, fromPayroll: fromPayroll, toPay: toPay, toSetAside: toSetAside)
    }

    /// Un ítem recurrente vencido solo se puede pagar si su `due` es el
    /// `nextPayment` actual del pago (evita pagar la 2ª ocurrencia antes
    /// que la 1ª). Los cargos siempre se pueden pagar.
    static func isNextPayable(_ item: QuincenaItem) -> Bool {
        if item.kind == .charges { return true }
        guard let next = item.payment.nextPayment else { return false }
        return startOfDay(item.due) == startOfDay(next)
    }

    /// Solo se puede diferir si el vencimiento está más allá de la
    /// quincena siguiente.
    static func canDefer(_ payment: ScheduledPayment, context: QuincenaContext) -> Bool {
        guard let next = payment.nextPayment else { return false }
        let dueIndex = findWindowIndex(context.windows, next)
        return dueIndex > context.currentIndex + 1
    }

    /// Plan del studio de diferir: reparte `amount` en `parts` fechas
    /// hacia atrás desde el vencimiento (semana -7 días, mes -1 mes,
    /// quincena -15 días). Nil si la primera fecha cae antes de hoy.
    static func deferPlan(amount: Double, due: Date, parts: Int, unit: String) -> [Date]? {
        guard parts >= 2 else { return nil }
        var dates: [Date] = []
        for i in (0..<parts).reversed() {
            let date: Date
            switch unit {
            case "week":
                date = calendar.date(byAdding: .day, value: -7 * i, to: due)!
            case "month":
                date = addingMonths(due, -i)
            default: // "fortnight"
                date = calendar.date(byAdding: .day, value: -15 * i, to: due)!
            }
            dates.append(date)
        }
        guard let first = dates.first, startOfDay(first) >= startOfDay(Date()) else { return nil }
        return dates
    }
}
