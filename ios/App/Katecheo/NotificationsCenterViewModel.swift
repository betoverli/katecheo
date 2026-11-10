import Foundation
import UIKit

/// Shared unread badge for the Caderno bell. Server unread is source of truth;
/// local mutations adjust optimistically until the next summary refresh.
enum KCNotificationsBadge {
    static let didChangeNotification = Notification.Name("katecheo.notifications.badge.changed")

    private(set) static var unreadCount: Int = 0

    /// Nil when zero; capped display `"99+"` above 99.
    static var displayText: String? {
        badgeText(for: unreadCount)
    }

    static func badgeText(for count: Int) -> String? {
        guard count > 0 else { return nil }
        if count > 99 { return "99+" }
        return String(count)
    }

    static func setUnreadCount(_ count: Int) {
        let next = max(0, count)
        guard next != unreadCount else { return }
        unreadCount = next
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func applyLocalRead(count: Int = 1) {
        setUnreadCount(unreadCount - max(0, count))
    }

    static func applyLocalMarkAllRead() {
        setUnreadCount(0)
    }

    @MainActor
    @discardableResult
    static func refreshFromServer() async -> Int {
        guard NativeAPIClient.hasBearer else {
            setUnreadCount(0)
            return 0
        }
        do {
            let summary = try await NativeAPIClient.notificationsSummary()
            setUnreadCount(summary.unread)
            return summary.unread
        } catch {
            return unreadCount
        }
    }
}

/// Pure helpers + async list state for the Notification Center screen.
@MainActor
final class NotificationsCenterViewModel {
    struct DaySection: Equatable {
        let title: String
        let items: [NativeAPIClient.InboxItemDTO]
    }

    private(set) var items: [NativeAPIClient.InboxItemDTO] = []
    private(set) var nextCursor: String?
    private(set) var unreadCount: Int = 0
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var loadGeneration = 0

    var onChange: (() -> Void)?

    var sections: [DaySection] {
        Self.groupByDay(items)
    }

    var hasUnread: Bool {
        items.contains { !$0.read } || unreadCount > 0
    }

    var showsEmpty: Bool {
        hasLoaded && errorMessage == nil && items.isEmpty && !isLoading
    }

    var showsError: Bool {
        hasLoaded && errorMessage != nil && items.isEmpty
    }

    func notifyChanged() {
        onChange?()
    }

    // MARK: - Loading

    func loadInitial(force: Bool = true) async {
        guard NativeAPIClient.hasBearer else {
            items = []
            nextCursor = nil
            unreadCount = 0
            KCNotificationsBadge.setUnreadCount(0)
            errorMessage = nil
            hasLoaded = true
            isLoading = false
            notifyChanged()
            return
        }
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        loadGeneration += 1
        let generation = loadGeneration
        notifyChanged()
        do {
            let page = try await NativeAPIClient.listNotifications(cursor: nil, limit: 40, unreadOnly: false)
            guard generation == loadGeneration else { return }
            items = page.items
            nextCursor = page.nextCursor
            unreadCount = page.unread
            KCNotificationsBadge.setUnreadCount(page.unread)
            hasLoaded = true
            isLoading = false
            errorMessage = nil
            notifyChanged()
        } catch {
            guard generation == loadGeneration else { return }
            isLoading = false
            hasLoaded = true
            if items.isEmpty {
                errorMessage = String(localized: "Não foi possível carregar os avisos.")
            }
            notifyChanged()
        }
    }

    func loadMoreIfNeeded(currentIndex: Int) async {
        guard !isLoading, !isLoadingMore else { return }
        guard let cursor = nextCursor, !cursor.isEmpty else { return }
        guard currentIndex >= items.count - 4 else { return }
        isLoadingMore = true
        notifyChanged()
        do {
            let page = try await NativeAPIClient.listNotifications(cursor: cursor, limit: 40, unreadOnly: false)
            let existing = Set(items.map(\.id))
            let appended = page.items.filter { !existing.contains($0.id) }
            items.append(contentsOf: appended)
            nextCursor = page.nextCursor
            unreadCount = page.unread
            KCNotificationsBadge.setUnreadCount(page.unread)
            isLoadingMore = false
            notifyChanged()
        } catch {
            isLoadingMore = false
            notifyChanged()
        }
    }

    // MARK: - Mark read

    @discardableResult
    func markRead(id: String) async -> Bool {
        guard !id.isEmpty else { return false }
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return false }
        if items[idx].read { return true }

        items[idx].read = true
        if unreadCount > 0 { unreadCount -= 1 }
        KCNotificationsBadge.applyLocalRead(count: 1)
        KCActivityStore.acknowledgeNotificationIds([id])
        notifyChanged()

        do {
            try await NativeAPIClient.markNotificationsRead(id: id)
            return true
        } catch {
            // Keep optimistic UI; next foreground/summary reconciles.
            return false
        }
    }

    @discardableResult
    func markAllRead() async -> Bool {
        let unreadIds = items.filter { !$0.read }.map(\.id)
        for i in items.indices where !items[i].read {
            items[i].read = true
        }
        unreadCount = 0
        KCNotificationsBadge.applyLocalMarkAllRead()
        if unreadIds.isEmpty {
            KCActivityStore.acknowledgeAllInboxNotifications()
        } else {
            KCActivityStore.acknowledgeNotificationIds(unreadIds)
            // Also clear any inbox-backed dots not present on the loaded pages.
            KCActivityStore.acknowledgeAllInboxNotifications()
        }
        notifyChanged()

        do {
            try await NativeAPIClient.markNotificationsRead(id: nil)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Presentation helpers (testable)

    static func groupByDay(
        _ items: [NativeAPIClient.InboxItemDTO],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DaySection] {
        var order: [String] = []
        var buckets: [String: [NativeAPIClient.InboxItemDTO]] = [:]
        for item in items {
            let title = dayTitle(for: parseDate(item.createdAt) ?? now, now: now, calendar: calendar)
            if buckets[title] == nil {
                order.append(title)
                buckets[title] = []
            }
            buckets[title, default: []].append(item)
        }
        return order.map { DaySection(title: $0, items: buckets[$0] ?? []) }
    }

    static func dayTitle(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Hoje")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Ontem")
        }
        return dayFormatter.string(from: date)
    }

    static func relativeTime(from createdAt: String, now: Date = Date()) -> String {
        guard let date = parseDate(createdAt) else { return "" }
        return relativeTime(from: date, now: now)
    }

    static func relativeTime(from date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 45 {
            return String(localized: "agora")
        }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    static func symbolName(forKind kind: String) -> String {
        switch kind {
        case "shares":
            return "square.and.arrow.up"
        case "groups":
            return "person.3"
        case "friends":
            return "person.badge.plus"
        case "reading":
            return "book"
        default:
            return "bell"
        }
    }

    static func parseDate(_ raw: String) -> Date? {
        if let date = isoFractional.date(from: raw) { return date }
        if let date = isoBasic.date(from: raw) { return date }
        if let date = dayOnly.date(from: String(raw.prefix(10))) { return date }
        return nil
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .current
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dayOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// Caderno nav-bar bell with a compact unread count badge.
final class KCNotificationsBellButton: UIControl {
    private let iconView = UIImageView()
    private let badgeLabel = UILabel()
    private let badgeBackground = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityTraits = .button
        accessibilityLabel = String(localized: "Avisos")

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = KCDesign.accent
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        iconView.image = UIImage(systemName: "bell")
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)

        badgeBackground.translatesAutoresizingMaskIntoConstraints = false
        badgeBackground.backgroundColor = KCDesign.danger
        badgeBackground.layer.cornerCurve = .continuous
        badgeBackground.isHidden = true
        badgeBackground.isUserInteractionEnabled = false
        addSubview(badgeBackground)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = UIFont.systemFont(ofSize: 11, weight: .bold).conditionallyScaled()
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeLabel.adjustsFontForContentSizeCategory = true
        badgeLabel.isUserInteractionEnabled = false
        badgeBackground.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 36),
            heightAnchor.constraint(equalToConstant: 36),

            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            badgeBackground.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            badgeBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 4),
            badgeBackground.heightAnchor.constraint(greaterThanOrEqualToConstant: 16),
            badgeBackground.widthAnchor.constraint(greaterThanOrEqualTo: badgeBackground.heightAnchor),

            badgeLabel.topAnchor.constraint(equalTo: badgeBackground.topAnchor, constant: 1),
            badgeLabel.bottomAnchor.constraint(equalTo: badgeBackground.bottomAnchor, constant: -1),
            badgeLabel.leadingAnchor.constraint(equalTo: badgeBackground.leadingAnchor, constant: 4),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeBackground.trailingAnchor, constant: -4),
        ])

        updateBadge(KCNotificationsBadge.displayText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateBadge(_ text: String?) {
        if let text, !text.isEmpty {
            badgeLabel.text = text
            badgeBackground.isHidden = false
            badgeBackground.layer.cornerRadius = 8
            accessibilityValue = text
        } else {
            badgeLabel.text = nil
            badgeBackground.isHidden = true
            accessibilityValue = nil
        }
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.55 : 1
        }
    }
}

private extension UIFont {
    func conditionallyScaled() -> UIFont {
        UIFontMetrics(forTextStyle: .caption2).scaledFont(for: self)
    }
}
