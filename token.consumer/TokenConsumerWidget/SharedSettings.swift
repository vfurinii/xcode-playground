import Foundation

enum SharedSettings {
    static let appGroupIdentifier = Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_IDENTIFIER") as? String ?? "group.example.token-consumer"
    static let keychainAccessGroup = Bundle.main.object(forInfoDictionaryKey: "KEYCHAIN_ACCESS_GROUP") as? String ?? "group.example.token-consumer"
    static let adminKeyAccount = "openai-admin-key"

    static let projectIDKey = "projectID"
    static let monthlyLimitKey = "monthlyLimit"
    static let monthlyBudgetUSDKey = "monthlyBudgetUSD"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}
