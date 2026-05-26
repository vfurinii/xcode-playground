import Foundation
import UserNotifications

enum UsageNotificationManager {
    static let threshold = 0.5

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func notifyIfNeeded(totalTokens: Int, monthlyLimit: Int, costUSD: Double?, monthlyBudgetUSD: Double) {
        let progress: Double
        if let costUSD, monthlyBudgetUSD > 0 {
            progress = costUSD / monthlyBudgetUSD
        } else {
            guard monthlyLimit > 0 else { return }
            progress = Double(totalTokens) / Double(monthlyLimit)
        }
        guard progress >= threshold else {
            resetIfNeeded()
            return
        }

        let monthKey = currentMonthKey()
        let sentKey = "usageNotification50Sent-\(monthKey)"
        guard !SharedSettings.defaults.bool(forKey: sentKey) else { return }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "OpenAI: 50% of budget used"
            content.body = notificationBody(totalTokens: totalTokens, monthlyLimit: monthlyLimit, costUSD: costUSD, monthlyBudgetUSD: monthlyBudgetUSD)
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "openai-token-usage-50-\(monthKey)",
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request) { error in
                if error == nil {
                    SharedSettings.defaults.set(true, forKey: sentKey)
                }
            }
        }
    }

    private static func notificationBody(totalTokens: Int, monthlyLimit: Int, costUSD: Double?, monthlyBudgetUSD: Double) -> String {
        if let costUSD, monthlyBudgetUSD > 0 {
            let percent = Int((costUSD / monthlyBudgetUSD * 100).rounded())
            return "\(percent)% used: \(costUSD.formatted(.currency(code: "USD"))) of \(monthlyBudgetUSD.formatted(.currency(code: "USD")))."
        }

        let percent = monthlyLimit > 0 ? Int((Double(totalTokens) / Double(monthlyLimit) * 100).rounded()) : 0
        let tokenText = "\(totalTokens.formatted()) of \(monthlyLimit.formatted()) tokens"
        if let costUSD {
            return "\(percent)% used: \(tokenText). Current cost: \(costUSD.formatted(.currency(code: "USD")))."
        }
        return "\(percent)% used: \(tokenText)."
    }

    private static func resetIfNeeded() {
        let previousMonthKey = SharedSettings.defaults.string(forKey: "usageNotificationMonth")
        let monthKey = currentMonthKey()
        if previousMonthKey != monthKey {
            SharedSettings.defaults.set(monthKey, forKey: "usageNotificationMonth")
        }
    }

    private static func currentMonthKey() -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: Date())
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }
}
