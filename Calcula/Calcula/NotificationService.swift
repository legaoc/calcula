import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift
import UserNotifications

/// Avisos fuera de la app para pagos programados (UNUserNotificationCenter).
/// La preferencia vive en UserDefaults con la misma clave que la web
/// (`calcula-reminders`). Los avisos se programan a las 09:00 del día
/// del pago, con identificador estable por pago.
@MainActor
final class NotificationService: ObservableObject {
    @AppStorage("calcula-reminders") var remindersEnabled = false
    @Published private(set) var authorized = false

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            authorized = granted
            return granted
        } catch {
            authorized = false
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorized = settings.authorizationStatus == .authorized
    }

    /// Reprograma todos los avisos desde Firestore, con el mismo formato
    /// que la web (`upcomingReminderItems` + `scheduleNativeReminders`):
    /// título = nombre del pago, cuerpo = "Hoy|Mañana|En N días · monto",
    /// a las 09:00 del día del vencimiento, solo dentro de la ventana de
    /// `daysBefore` (por defecto 2 días, de settings/reminders).
    /// Si el ajuste está apagado, borra los pendientes.
    func rescheduleAll(uid: String) async {
        let center = UNUserNotificationCenter.current()
        guard remindersEnabled else {
            center.removeAllPendingNotificationRequests()
            return
        }
        guard await requestAuthorization() else { return }
        center.removeAllPendingNotificationRequests()

        let db = Firestore.firestore()
        do {
            let settingsDoc = try await db.collection("users").document(uid)
                .collection("settings").document("reminders").getDocument()
            let daysBefore = (try? settingsDoc.data(as: ReminderSettings.self))?.daysBefore ?? 2
            let snapshot = try await db.collection("users").document(uid)
                .collection("scheduledPayments")
                .whereField("active", isEqualTo: true)
                .getDocuments()
            let startOfToday = Calendar.current.startOfDay(for: Date())
            for doc in snapshot.documents {
                guard let payment = try? doc.data(as: ScheduledPayment.self),
                      let id = payment.id,
                      let next = payment.nextPayment
                else { continue }
                let days = Calendar.current.dateComponents(
                    [.day], from: startOfToday,
                    to: Calendar.current.startOfDay(for: next)
                ).day ?? 0
                guard days >= 0, days <= daysBefore else { continue }
                let relative: String
                switch days {
                case 0: relative = "Hoy"
                case 1: relative = "Mañana"
                default: relative = "En \(days) días"
                }
                let content = UNMutableNotificationContent()
                content.title = payment.name
                content.body = "\(relative) · \(Format.money(payment.amount))"
                content.sound = .default
                var components = Calendar.current.dateComponents(
                    [.year, .month, .day], from: next
                )
                components.hour = 9
                components.minute = 0
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: components, repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: "calcula-payment-\(id)",
                    content: content,
                    trigger: trigger
                )
                try await center.add(request)
            }
        } catch {
            // Sin red o sin permisos: los avisos quedan pendientes para
            // el próximo arranque; no se bloquea la app por esto.
        }
    }
}
