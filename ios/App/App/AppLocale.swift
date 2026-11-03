import Foundation
import UIKit

/// Maps the iPhone / per-app language onto Verse2Note API locale codes (`pt` / `en` / `es`).
enum AppLocale {
    /// API / prefs locale derived from `Locale.preferredLanguages` (system or per-app).
    static var apiCode: String {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "pt-br"
        if preferred.hasPrefix("en") { return "en" }
        if preferred.hasPrefix("es") { return "es" }
        return "pt"
    }

    /// Human label for the current interface language (localized).
    static var interfaceLanguageLabel: String {
        switch apiCode {
        case "en":
            return String(localized: "English")
        case "es":
            return String(localized: "Español")
        default:
            return String(localized: "Português")
        }
    }

    /// Label for a Bible-reference (`copyLocale`) preference id.
    static func copyLocaleLabel(_ id: String) -> String {
        switch id {
        case "en":
            return String(localized: "English")
        case "es":
            return String(localized: "Español")
        default:
            return String(localized: "Português")
        }
    }

    /// Opens the system Settings page for this app (per-app language lives there).
    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Locale-aware display formatters (data wire format stays POSIX / ISO)

    /// Parses `yyyy-MM-dd` (storage) and formats for the current locale.
    static func displayDay(_ yyyyMMdd: String) -> String {
        guard let date = dayStorageFormatter.date(from: yyyyMMdd) else { return yyyyMMdd }
        return dayDisplayFormatter.string(from: date)
    }

    static func formatCount(_ value: Int) -> String {
        countFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static let dayStorageFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dayDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter
    }()

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        return formatter
    }()
}
