import Foundation

// MARK: - Cálculos de Finanzas (port fiel de la web: MAP.md §4.6–4.8)

enum FinancePeriod: String, CaseIterable {
    case day
    case week
    case month
    case year

    var label: String {
        switch self {
        case .day: return "Día"
        case .week: return "Semana"
        case .month: return "Mes"
        case .year: return "Año"
        }
    }
}

struct PeriodBounds {
    var start: Date
    var end: Date
    var prevStart: Date
    var prevEnd: Date
}

struct ChartBucket: Identifiable {
    var id: Int { index }
    var index: Int
    var label: String
    var amount: Double
    var isNow: Bool
}

enum FinanceCalc {
    static let calendar = Calendar.current

    // MARK: - Periodos

    /// Límites del periodo actual y del anterior (para el delta).
    /// Semana = lunes–domingo; mes = día 1–día 1; año = 1 ene–1 ene.
    static func bounds(for period: FinancePeriod, now: Date = Date()) -> PeriodBounds {
        let cal = calendar
        switch period {
        case .day:
            let start = cal.startOfDay(for: now)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            return PeriodBounds(start: start, end: end,
                                prevStart: cal.date(byAdding: .day, value: -1, to: start)!,
                                prevEnd: start)
        case .week:
            let weekday = cal.component(.weekday, from: now) // 1 = domingo
            let mondayOffset = (weekday + 5) % 7
            let start = cal.date(byAdding: .day, value: -mondayOffset, to: cal.startOfDay(for: now))!
            let end = cal.date(byAdding: .day, value: 7, to: start)!
            return PeriodBounds(start: start, end: end,
                                prevStart: cal.date(byAdding: .day, value: -7, to: start)!,
                                prevEnd: start)
        case .month:
            let start = cal.date(from: DateComponents(
                year: cal.component(.year, from: now),
                month: cal.component(.month, from: now), day: 1))!
            let end = cal.date(byAdding: .month, value: 1, to: start)!
            let prevEnd = start
            let prevStart = cal.date(byAdding: .month, value: -1, to: start)!
            return PeriodBounds(start: start, end: end, prevStart: prevStart, prevEnd: prevEnd)
        case .year:
            let start = cal.date(from: DateComponents(
                year: cal.component(.year, from: now), month: 1, day: 1))!
            let end = cal.date(byAdding: .year, value: 1, to: start)!
            let prevStart = cal.date(byAdding: .year, value: -1, to: start)!
            return PeriodBounds(start: start, end: end, prevStart: prevStart, prevEnd: start)
        }
    }

    // MARK: - Gasto

    /// Solo cargo y pago cuentan como gasto; abono no.
    static func spendAmount(_ movement: Movement) -> Double {
        switch movement.type.lowercased() {
        case "cargo", "pago": return movement.amount
        default: return 0
        }
    }

    static func sumSpend(_ movements: [Movement], from: Date, to: Date) -> Double {
        movements
            .filter { ($0.createdAt ?? .distantPast) >= from && ($0.createdAt ?? .distantPast) < to }
            .map(spendAmount)
            .reduce(0, +)
    }

    /// Gasto del mes en curso por categoría. "all" suma todo; "subs"
    /// suma además los movimientos de cuentas de suscripción/recurrentes.
    static func monthSpendByCategory(
        _ movements: [Movement], category: String, accounts: [Account], now: Date = Date()
    ) -> Double {
        let bounds = bounds(for: .month, now: now)
        let inMonth = movements.filter {
            ($0.createdAt ?? .distantPast) >= bounds.start && ($0.createdAt ?? .distantPast) < bounds.end
        }
        if category == "all" {
            return inMonth.map(spendAmount).reduce(0, +)
        }
        return inMonth.filter { movement in
            if category == "subs" {
                let account = accounts.first { $0.id == movement.accountId }
                return (account?.isSubscription ?? false) || account?.type == "recurring"
            }
            return (movement.category ?? "otros") == category
        }.map(spendAmount).reduce(0, +)
    }

    // MARK: - Gráfica

    /// Barras de gasto: día/semana → 7 días; mes → días del mes (1 barra
    /// cada 1–2 días); año → 12 meses.
    static func buckets(for period: FinancePeriod, movements: [Movement], now: Date = Date()) -> [ChartBucket] {
        let cal = calendar
        switch period {
        case .day, .week:
            let bounds = bounds(for: period, now: now)
            let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: bounds.start)! }
            let weekdayLetters = ["D", "L", "M", "X", "J", "V", "S"]
            return days.enumerated().map { index, day in
                let next = cal.date(byAdding: .day, value: 1, to: day)!
                let letter = weekdayLetters[cal.component(.weekday, from: day) - 1]
                return ChartBucket(
                    index: index,
                    label: letter,
                    amount: sumSpend(movements, from: day, to: next),
                    isNow: cal.isDate(day, inSameDayAs: now)
                )
            }
        case .month:
            let bounds = bounds(for: .month, now: now)
            let daysInMonth = cal.range(of: .day, in: .month, for: bounds.start)!.count
            let step = daysInMonth > 16 ? 2 : 1
            var result: [ChartBucket] = []
            var index = 0
            var day = 1
            while day <= daysInMonth {
                let from = cal.date(from: DateComponents(
                    year: cal.component(.year, from: bounds.start),
                    month: cal.component(.month, from: bounds.start), day: day))!
                let to = cal.date(byAdding: .day, value: step, to: from)!
                result.append(ChartBucket(
                    index: index,
                    label: "\(day)",
                    amount: sumSpend(movements, from: from, to: to),
                    isNow: cal.component(.day, from: now) >= day
                        && cal.component(.day, from: now) < day + step
                        && cal.isDate(now, equalTo: bounds.start, toGranularity: .month)
                ))
                index += 1
                day += step
            }
            return result
        case .year:
            let year = cal.component(.year, from: now)
            return (1...12).map { month in
                let from = cal.date(from: DateComponents(year: year, month: month, day: 1))!
                let to = cal.date(byAdding: .month, value: 1, to: from)!
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "es_MX")
                formatter.dateFormat = "MMM"
                return ChartBucket(
                    index: month - 1,
                    label: formatter.string(from: from).replacingOccurrences(of: ".", with: ""),
                    amount: sumSpend(movements, from: from, to: to),
                    isNow: cal.component(.month, from: now) == month
                )
            }
        }
    }

    // MARK: - Presupuestos y metas

    /// `{spent, cap, pct, level}`: level "hot" ≥100%, "warn" ≥80%.
    static func budgetStatus(budget: Budget, spent: Double) -> (spent: Double, cap: Double, pct: Int, level: String) {
        let pct = budget.amount > 0 ? min(100, Int((spent / budget.amount * 100).rounded())) : 0
        let level = pct >= 100 ? "hot" : pct >= 80 ? "warn" : ""
        return (spent: spent, cap: budget.amount, pct: pct, level: level)
    }

    /// Días restantes (mín. 1) → periodos según cadencia.
    static func periodsUntil(deadline: Date, cadence: String, now: Date = Date()) -> Int {
        let days = max(1, calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: deadline)
        ).day ?? 1)
        switch cadence {
        case "daily": return days
        case "weekly": return Int(ceil(Double(days) / 7))
        case "monthly": return Int(ceil(Double(days) / 30))
        default: return Int(ceil(Double(days) / 15)) // fortnightly
        }
    }

    static func goalStatus(goal: Goal, now: Date = Date()) -> (left: Double, periods: Int, each: Double, pct: Int) {
        let left = max(0, goal.target - goal.saved)
        let periods = goal.deadline.map { periodsUntil(deadline: $0, cadence: goal.cadence, now: now) } ?? 1
        let each = left / Double(max(1, periods))
        let pct = goal.target > 0 ? min(100, Int((goal.saved / goal.target * 100).rounded())) : 0
        return (left: left, periods: periods, each: each, pct: pct)
    }
}
