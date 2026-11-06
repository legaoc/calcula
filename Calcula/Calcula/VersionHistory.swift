import Foundation
import SwiftUI

/// Versión de la app leída del Bundle (nunca escrita a mano).
/// MARKETING_VERSION → CFBundleShortVersionString,
/// CURRENT_PROJECT_VERSION → CFBundleVersion.
enum AppVersion {
    static var short: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    /// "Calcula 1.0 (build 1)".
    static var display: String { "Calcula \(short) (build \(build))" }
}

struct VersionEntry: Identifiable {
    var id: String { version }
    var version: String
    var title: String
    var date: String?
    var changes: [String]
}

/// Historial de versiones leído del CHANGELOG.md incluido en el bundle
/// (la misma fuente que el archivo del repo; sin red para mostrarlo).
enum VersionHistory {
    static func load() -> [VersionEntry] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return parse(text)
    }

    /// Formatos aceptados en cada `##`:
    /// "1.0 — Primera versión nativa", "1.1 — 2026-11-20 — Título",
    /// "[1.1] - 2026-11-20", "Unreleased — Título".
    static func parse(_ text: String) -> [VersionEntry] {
        var entries: [VersionEntry] = []
        var current: VersionEntry?
        func flush() {
            if let entry = current { entries.append(entry) }
            current = nil
        }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                flush()
                let heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                // Separa por "—" o " - ".
                let parts = heading
                    .components(separatedBy: "—")
                    .flatMap { $0.components(separatedBy: " - ") }
                    .map {
                        $0.trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    }
                    .filter { !$0.isEmpty }
                guard let version = parts.first else { continue }
                var date: String?
                var titleParts = Array(parts.dropFirst())
                if let first = titleParts.first, isDate(first) {
                    date = first
                    titleParts = Array(titleParts.dropFirst())
                }
                current = VersionEntry(
                    version: version,
                    title: titleParts.joined(separator: " — "),
                    date: date,
                    changes: []
                )
            } else if line.hasPrefix("- "), current != nil {
                current?.changes.append(String(line.dropFirst(2)))
            }
        }
        flush()
        return entries
    }

    private static func isDate(_ text: String) -> Bool {
        let parts = text.split(separator: "-")
        return parts.count == 3
            && parts[0].count == 4
            && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}

/// Pantalla de Ajustes → Historial de versiones.
struct VersionHistoryView: View {
    private var entries: [VersionEntry] { VersionHistory.load() }

    var body: some View {
        List {
            if entries.isEmpty {
                Text("No hay historial disponible.")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.version)
                                .font(.headline)
                            if entry.version == AppVersion.short {
                                Text("Actual")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.calculaAccent)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            if let date = entry.date {
                                Text(date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !entry.title.isEmpty {
                            Text(entry.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(entry.changes, id: \.self) { change in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                Text(change)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Historial de versiones")
    }
}
