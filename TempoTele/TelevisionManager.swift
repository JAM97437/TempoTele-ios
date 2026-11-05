import Foundation
import Combine
import UserNotifications
import AudioToolbox

struct ChoreRecord: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var startedAt: Date
    var elapsedSeconds: TimeInterval
    var adjustmentSeconds: TimeInterval
    var weekendKey: String
}

@MainActor
final class TelevisionManager: ObservableObject {
    @Published private(set) var secondsUsedToday: TimeInterval = 0
    @Published private(set) var sessionStart: Date?
    @Published private(set) var history: [String: TimeInterval] = [:]
    @Published private(set) var choreStart: Date?
    @Published private(set) var activeChoreTitle: String = ""
    @Published private(set) var activeChoreWeekend: String = ""
    @Published private(set) var choreElapsed: TimeInterval = 0
    @Published private(set) var choreRecords: [ChoreRecord] = []
    @Published var dailyLimitMinutes: Int = 60 {
        didSet { defaults.set(dailyLimitMinutes, forKey: Keys.limit); scheduleLimitAlert() }
    }
    // Initial credit for each day can be configured independently.
    // The sum is the initial credit for the whole weekend.
    @Published var saturdayInitialMinutes: Int = 60 {
        didSet { defaults.set(saturdayInitialMinutes, forKey: Keys.saturdayInitial); scheduleLimitAlert() }
    }
    @Published var sundayInitialMinutes: Int = 60 {
        didSet { defaults.set(sundayInitialMinutes, forKey: Keys.sundayInitial); scheduleLimitAlert() }
    }
    @Published var childName: String = "Ma fille" {
        didSet { defaults.set(childName, forKey: Keys.name) }
    }

    private let defaults = UserDefaults.standard
    private let calendar = Calendar.current
    private var ticker: Timer?
    private var thirtySecondSoundPlayed = false
    private enum Keys {
        static let history = "watchHistoryV1"
        static let start = "activeSessionStartV1"
        static let limit = "dailyLimitMinutesV1"
        static let weekendLimit = "weekendLimitMinutesV2" // migration from v3
        static let saturdayInitial = "saturdayInitialMinutesV4"
        static let sundayInitial = "sundayInitialMinutesV4"
        static let name = "childNameV1"
        static let choreStart = "choreStartV2"
        static let choreTitle = "choreTitleV2"
        static let choreWeekend = "choreWeekendV2"
        static let choreRecords = "choreRecordsV2"
        static let notificationID = "television-limit"
        static let choreWarningID = "chore-warning"
        static let choreDeadlineID = "chore-deadline"
    }

    init() {
        let savedDaily = defaults.integer(forKey: Keys.limit)
        dailyLimitMinutes = savedDaily == 0 ? 60 : savedDaily
        // Preserve the amount set in version 3, then allow a different
        // initial limit for Saturday and Sunday. Zero is a valid limit.
        let oldTotal = (defaults.object(forKey: Keys.weekendLimit) as? Int) ?? 120
        let originalSaturday = oldTotal / 2
        let originalSunday = oldTotal - originalSaturday
        saturdayInitialMinutes = (defaults.object(forKey: Keys.saturdayInitial) as? Int) ?? originalSaturday
        sundayInitialMinutes = (defaults.object(forKey: Keys.sundayInitial) as? Int) ?? originalSunday
        childName = defaults.string(forKey: Keys.name) ?? "Ma fille"
        history = defaults.dictionary(forKey: Keys.history) as? [String: TimeInterval] ?? [:]
        sessionStart = defaults.object(forKey: Keys.start) as? Date
        choreStart = defaults.object(forKey: Keys.choreStart) as? Date
        activeChoreTitle = defaults.string(forKey: Keys.choreTitle) ?? ""
        activeChoreWeekend = defaults.string(forKey: Keys.choreWeekend) ?? ""
        if let data = defaults.data(forKey: Keys.choreRecords),
           let records = try? JSONDecoder().decode([ChoreRecord].self, from: data) {
            choreRecords = records
        }
        thirtySecondSoundPlayed = choreStart.map { Date().timeIntervalSince($0) >= 270 } ?? false
        refresh()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if choreStart != nil { scheduleChoreAlerts() }
        scheduleLimitAlert()
    }

    var isRunning: Bool { sessionStart != nil }
    var isChoreRunning: Bool { choreStart != nil }
    var isWeekend: Bool { let weekday = calendar.component(.weekday, from: Date()); return weekday == 1 || weekday == 7 }

    // All week keys designate the Saturday of the relevant weekend, in local time.
    private func saturday(for date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let daysAhead = (7 - weekday + 7) % 7
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: daysAhead, to: date) ?? date)
    }
    private func saturdayForCurrentOrUpcomingWeekend() -> Date {
        if calendar.component(.weekday, from: Date()) == 1 {
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        }
        return saturday(for: Date())
    }
    var currentWeekendKey: String { key(for: saturdayForCurrentOrUpcomingWeekend()) }
    var weekendDateDescription: String {
        let saturday = saturdayForCurrentOrUpcomingWeekend()
        let sunday = calendar.date(byAdding: .day, value: 1, to: saturday)!
        return "\(saturday.formatted(.dateTime.day().month(.wide))) – \(sunday.formatted(.dateTime.day().month(.wide)))"
    }
    var weekendRecords: [ChoreRecord] { choreRecords.filter { $0.weekendKey == currentWeekendKey }.reversed() }
    var weekendBonusSeconds: TimeInterval {
        weekendRecords.reduce(0) { $0 + max(0, $1.adjustmentSeconds) }
    }
    var weekendPenaltySeconds: TimeInterval {
        weekendRecords.reduce(0) { $0 + max(0, -$1.adjustmentSeconds) }
    }
    var weekendEarnedBonusMinutes: Int { Int(weekendBonusSeconds / 60) }
    // The initial allowance is different for each day if the parent wishes.
    // Bonuses and penalties are always split equally (50/50).
    // Unused minutes are never transferred between the two days.
    var weekendLimitMinutes: Int { saturdayInitialMinutes + sundayInitialMinutes }
    var saturdayInitialSeconds: TimeInterval { TimeInterval(saturdayInitialMinutes * 60) }
    var sundayInitialSeconds: TimeInterval { TimeInterval(sundayInitialMinutes * 60) }
    var weekendDailyBonusSeconds: TimeInterval { weekendBonusSeconds / 2 }
    var weekendDailyPenaltySeconds: TimeInterval { weekendPenaltySeconds / 2 }
    var saturdayAllowedSeconds: TimeInterval {
        max(0, saturdayInitialSeconds + weekendDailyBonusSeconds - weekendDailyPenaltySeconds)
    }
    var sundayAllowedSeconds: TimeInterval {
        max(0, sundayInitialSeconds + weekendDailyBonusSeconds - weekendDailyPenaltySeconds)
    }
    var weekendAllowedSeconds: TimeInterval { saturdayAllowedSeconds + sundayAllowedSeconds }
    var saturdayDate: Date { saturdayForCurrentOrUpcomingWeekend() }
    var sundayDate: Date { calendar.date(byAdding: .day, value: 1, to: saturdayDate)! }
    var saturdayUsedSeconds: TimeInterval { secondsUsed(on: saturdayDate) }
    var sundayUsedSeconds: TimeInterval { secondsUsed(on: sundayDate) }
    var saturdayRemainingSeconds: TimeInterval { max(0, saturdayAllowedSeconds - saturdayUsedSeconds) }
    var sundayRemainingSeconds: TimeInterval { max(0, sundayAllowedSeconds - sundayUsedSeconds) }
    var weekendUsedSeconds: TimeInterval { saturdayUsedSeconds + sundayUsedSeconds }
    var weekendRemainingSeconds: TimeInterval { saturdayRemainingSeconds + sundayRemainingSeconds }
    var dailyLimitSeconds: TimeInterval { TimeInterval(dailyLimitMinutes * 60) }
    var remainingSeconds: TimeInterval {
        switch calendar.component(.weekday, from: Date()) {
        case 7: return saturdayRemainingSeconds
        case 1: return sundayRemainingSeconds
        default: return max(0, dailyLimitSeconds - secondsUsedToday)
        }
    }
    var todayAllowedSeconds: TimeInterval {
        switch calendar.component(.weekday, from: Date()) {
        case 7: return saturdayAllowedSeconds
        case 1: return sundayAllowedSeconds
        default: return dailyLimitSeconds
        }
    }
    var progress: Double {
        let allowance = todayAllowedSeconds
        let used = secondsUsedToday
        return allowance > 0 ? min(1, used / allowance) : 1
    }
    var hasReachedLimit: Bool { remainingSeconds <= 0 }
    var choreSecondsRemaining: TimeInterval { max(0, 300 - choreElapsed) }

    func start() {
        guard sessionStart == nil, !hasReachedLimit else { return }
        sessionStart = Date()
        defaults.set(sessionStart, forKey: Keys.start)
        scheduleLimitAlert()
        refresh()
    }
    func stop() {
        guard let start = sessionStart else { return }
        addUsage(from: start, to: Date())
        sessionStart = nil
        defaults.removeObject(forKey: Keys.start)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Keys.notificationID])
        refresh()
    }

    func startChore(title: String) {
        guard choreStart == nil else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        activeChoreTitle = trimmed.isEmpty ? "Demande" : trimmed
        activeChoreWeekend = currentWeekendKey
        choreStart = Date()
        thirtySecondSoundPlayed = false
        defaults.set(activeChoreTitle, forKey: Keys.choreTitle)
        defaults.set(activeChoreWeekend, forKey: Keys.choreWeekend)
        defaults.set(choreStart, forKey: Keys.choreStart)
        choreElapsed = 0
        scheduleChoreAlerts()
    }

    func finishChore() {
        guard let started = choreStart else { return }
        let elapsed = max(0, Date().timeIntervalSince(started))
        let target = activeChoreWeekend
        let previousBonuses = choreRecords.filter { $0.weekendKey == target }
            .reduce(0.0) { $0 + max(0, $1.adjustmentSeconds) }
        // Before or at 5:00: +5 minutes, up to 20 minutes per weekend.
        // After 5:00: deduct the ENTIRE time since the request, not just the excess.
        let adjustment: TimeInterval = elapsed <= 300
            ? min(300, max(0, 1200 - previousBonuses))
            : -ceil(elapsed)
        choreRecords.append(ChoreRecord(title: activeChoreTitle, startedAt: started,
                                        elapsedSeconds: elapsed, adjustmentSeconds: adjustment,
                                        weekendKey: target))
        if let data = try? JSONEncoder().encode(choreRecords) {
            defaults.set(data, forKey: Keys.choreRecords)
        }
        choreStart = nil
        activeChoreTitle = ""
        activeChoreWeekend = ""
        choreElapsed = 0
        defaults.removeObject(forKey: Keys.choreStart)
        defaults.removeObject(forKey: Keys.choreTitle)
        defaults.removeObject(forKey: Keys.choreWeekend)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Keys.choreWarningID, Keys.choreDeadlineID])
        refresh()
        scheduleLimitAlert()
    }

    func refresh() {
        secondsUsedToday = secondsUsed(on: Date())
        if let started = choreStart {
            let elapsed = max(0, Date().timeIntervalSince(started))
            choreElapsed = elapsed
            if elapsed >= 270 && !thirtySecondSoundPlayed {
                thirtySecondSoundPlayed = true
                AudioServicesPlaySystemSound(1005)
            }
        }
    }

    func secondsUsed(on date: Date) -> TimeInterval {
        let stored = history[key(for: date)] ?? 0
        guard let start = sessionStart else { return stored }
        let now = Date()
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return stored }
        return stored + max(0, min(now, dayEnd).timeIntervalSince(max(start, dayStart)))
    }

    private func key(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    private func addUsage(from start: Date, to end: Date) {
        guard end > start else { return }
        var cursor = start
        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let chunkEnd = min(end, nextDay)
            history[key(for: cursor), default: 0] += chunkEnd.timeIntervalSince(cursor)
            cursor = chunkEnd
        }
        defaults.set(history, forKey: Keys.history)
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
            Task { @MainActor in
                self?.scheduleLimitAlert()
                self?.scheduleChoreAlerts()
            }
        }
    }

    private func scheduleLimitAlert() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Keys.notificationID])
        guard sessionStart != nil else { return }
        let remaining = remainingSeconds
        guard remaining > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Temps de télévision terminé"
        content.body = "Le temps de télévision disponible est écoulé."
        content.sound = .default
        let request = UNNotificationRequest(identifier: Keys.notificationID, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false))
        UNUserNotificationCenter.current().add(request)
    }
    private func scheduleChoreAlerts() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Keys.choreWarningID, Keys.choreDeadlineID])
        guard let started = choreStart else { return }
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < 270 {
            let content = UNMutableNotificationContent()
            content.title = "Plus que 30 secondes !"
            content.body = "Il reste 30 secondes pour commencer : \(activeChoreTitle)."
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Keys.choreWarningID,
                content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, 270 - elapsed), repeats: false)))
        }
        if elapsed < 300 {
            let content = UNMutableNotificationContent()
            content.title = "Les 5 minutes sont écoulées"
            content.body = "Le retard sera déduit du crédit télévision jusqu’à l’arrêt du chronomètre."
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Keys.choreDeadlineID,
                content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, 300 - elapsed), repeats: false)))
        }
    }
}
