//
//  TokenConsumerWidget.swift
//  TokenConsumerWidget
//
//  Created by Vitor Furini on 25/05/26.
//

import WidgetKit
import SwiftUI
import Foundation

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TokenUsageEntry {
        TokenUsageEntry(date: Date(), configuration: ConfigurationAppIntent(), usage: .preview)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> TokenUsageEntry {
        TokenUsageEntry(date: Date(), configuration: configuration, usage: .preview)
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<TokenUsageEntry> {
        let currentDate = Date()
        let defaults = SharedSettings.defaults
        let savedAdminKey = KeychainStore.readAdminKey()
        let usage = await TokenUsageClient.fetch(
            adminKey: savedAdminKey.isEmpty ? configuration.adminKey : savedAdminKey,
            projectID: defaults.string(forKey: SharedSettings.projectIDKey) ?? "",
            fallbackTokenLimit: configuredMonthlyLimit(defaults),
            fallbackBudgetUSD: defaults.double(forKey: SharedSettings.monthlyBudgetUSDKey)
        )
        UsageNotificationManager.notifyIfNeeded(
            totalTokens: usage.totalTokens,
            monthlyLimit: usage.monthlyLimit,
            costUSD: usage.costUSD,
            monthlyBudgetUSD: usage.monthlyBudgetUSD
        )

        let entry = TokenUsageEntry(date: currentDate, configuration: configuration, usage: usage)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 5, to: currentDate) ?? currentDate.addingTimeInterval(300)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

//    func relevances() async -> WidgetRelevances<ConfigurationAppIntent> {
//        // Generate a list containing the contexts this widget is relevant in.
//    }
}

private func configuredMonthlyLimit(_ defaults: UserDefaults) -> Int {
    let value = defaults.integer(forKey: SharedSettings.monthlyLimitKey)
    return value > 0 ? value : 1000000
}

struct TokenUsageEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let usage: TokenUsageSnapshot
}

struct TokenConsumerWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        TokenUsageWidgetView(entry: entry)
    }
}

struct TokenUsageWidgetView: View {
    let entry: TokenUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Image("TokenPulseLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("OpenAI")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let message = entry.usage.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sem dados")
                        .font(.headline)
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.usage.primaryCostText)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)

                    ProgressView(value: entry.usage.budgetProgress)
                        .tint(entry.usage.budgetProgress > 0.85 ? .red : .green)

                    if entry.usage.monthlyBudgetUSD > 0 {
                        Text("de \(entry.usage.monthlyBudgetUSD, format: .currency(code: "USD")) no mes")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack {
                        UsageStat(label: "Tokens", value: entry.usage.totalTokens)
                        UsageStat(label: "Req.", value: entry.usage.requestCount)
                    }
                }
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.13, blue: 0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .foregroundStyle(.white)
    }
}

struct UsageStat: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TokenConsumerWidget: Widget {
    let kind: String = "TokenConsumerWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            TokenConsumerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AI Token Usage")
        .description("Shows your OpenAI token consumption for the current month.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TokenUsageSnapshot {
    var totalTokens: Int
    var inputTokens: Int
    var outputTokens: Int
    var requestCount: Int
    var monthlyLimit: Int
    var costUSD: Double?
    var model: String?
    var monthlyBudgetUSD: Double
    var errorMessage: String?

    var limitProgress: Double {
        guard monthlyLimit > 0 else { return 0 }
        return min(Double(totalTokens) / Double(monthlyLimit), 1)
    }

    var budgetProgress: Double {
        guard let costUSD, monthlyBudgetUSD > 0 else { return limitProgress }
        return min(costUSD / monthlyBudgetUSD, 1)
    }

    var primaryCostText: String {
        guard let costUSD else { return "US$ --" }
        return costUSD.formatted(.currency(code: "USD"))
    }

    static let preview = TokenUsageSnapshot(
        totalTokens: 128420,
        inputTokens: 91200,
        outputTokens: 37220,
        requestCount: 84,
        monthlyLimit: 1000000,
        costUSD: 14.72,
        model: "gpt-5",
        monthlyBudgetUSD: 50,
        errorMessage: nil
    )

    static func failure(_ message: String, fallbackTokenLimit: Int, fallbackBudgetUSD: Double) -> TokenUsageSnapshot {
        TokenUsageSnapshot(
            totalTokens: 0,
            inputTokens: 0,
            outputTokens: 0,
            requestCount: 0,
            monthlyLimit: fallbackTokenLimit,
            costUSD: nil,
            model: nil,
            monthlyBudgetUSD: fallbackBudgetUSD,
            errorMessage: message
        )
    }

    init(totalTokens: Int, inputTokens: Int, outputTokens: Int, requestCount: Int, monthlyLimit: Int, costUSD: Double?, model: String?, monthlyBudgetUSD: Double, errorMessage: String?) {
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.requestCount = requestCount
        self.monthlyLimit = monthlyLimit
        self.costUSD = costUSD
        self.model = model
        self.monthlyBudgetUSD = monthlyBudgetUSD
        self.errorMessage = errorMessage
    }
}

enum TokenUsageClient {
    static func fetch(adminKey: String, projectID: String, fallbackTokenLimit: Int, fallbackBudgetUSD: Double) async -> TokenUsageSnapshot {
        guard !adminKey.isEmpty else {
            return .failure("Configure uma OpenAI Admin Key.", fallbackTokenLimit: fallbackTokenLimit, fallbackBudgetUSD: fallbackBudgetUSD)
        }

        do {
            async let usageResponse = fetchCompletionUsage(adminKey: adminKey, projectID: projectID)
            async let costsResponse = fetchCosts(adminKey: adminKey, projectID: projectID)
            let usage = try await usageResponse
            let cost = try? await costsResponse

            return TokenUsageSnapshot(
                totalTokens: usage.inputTokens + usage.outputTokens,
                inputTokens: usage.inputTokens,
                outputTokens: usage.outputTokens,
                requestCount: usage.requestCount,
                monthlyLimit: fallbackTokenLimit,
                costUSD: cost,
                model: nil,
                monthlyBudgetUSD: fallbackBudgetUSD,
                errorMessage: nil
            )
        } catch {
            return .failure(error.localizedDescription, fallbackTokenLimit: fallbackTokenLimit, fallbackBudgetUSD: fallbackBudgetUSD)
        }
    }

    private static func fetchCompletionUsage(adminKey: String, projectID: String) async throws -> CompletionUsageTotal {
        let startTime = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        var components = URLComponents(string: "https://api.openai.com/v1/organization/usage/completions")!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(Int(startTime.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31")
        ]
        if !projectID.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "project_ids[]", value: projectID))
        }

        let response: OpenAIUsageResponse = try await request(components.url!, adminKey: adminKey)
        return response.total
    }

    private static func fetchCosts(adminKey: String, projectID: String) async throws -> Double {
        let startTime = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        var components = URLComponents(string: "https://api.openai.com/v1/organization/costs")!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(Int(startTime.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31")
        ]
        if !projectID.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "project_ids[]", value: projectID))
        }

        let response: OpenAICostsResponse = try await request(components.url!, adminKey: adminKey)
        return response.total
    }

    private static func request<Response: Decodable>(_ url: URL, adminKey: String) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(sanitizeAdminKey(adminKey))", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw TokenUsageError.httpStatus(httpResponse.statusCode, WidgetOpenAIErrorResponse.message(from: data))
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func sanitizeAdminKey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("bearer ") {
            return String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}

struct OpenAIUsageResponse: Decodable {
    let data: [UsageBucket]

    var total: CompletionUsageTotal {
        data.reduce(CompletionUsageTotal(inputTokens: 0, outputTokens: 0, requestCount: 0)) { partial, bucket in
            let bucketTotal = bucket.results.reduce(CompletionUsageTotal(inputTokens: 0, outputTokens: 0, requestCount: 0)) { resultPartial, result in
                CompletionUsageTotal(
                    inputTokens: resultPartial.inputTokens + result.inputTokens + result.inputAudioTokens,
                    outputTokens: resultPartial.outputTokens + result.outputTokens + result.outputAudioTokens,
                    requestCount: resultPartial.requestCount + result.requestCount
                )
            }
            return CompletionUsageTotal(
                inputTokens: partial.inputTokens + bucketTotal.inputTokens,
                outputTokens: partial.outputTokens + bucketTotal.outputTokens,
                requestCount: partial.requestCount + bucketTotal.requestCount
            )
        }
    }
}

struct UsageBucket: Decodable {
    let results: [CompletionUsageResult]
}

struct CompletionUsageResult: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let inputAudioTokens: Int
    let outputAudioTokens: Int
    let requestCount: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case inputAudioTokens = "input_audio_tokens"
        case outputAudioTokens = "output_audio_tokens"
        case requestCount = "num_model_requests"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.inputTokens = (try? container.decode(Int.self, forKey: .inputTokens)) ?? 0
        self.outputTokens = (try? container.decode(Int.self, forKey: .outputTokens)) ?? 0
        self.inputAudioTokens = (try? container.decode(Int.self, forKey: .inputAudioTokens)) ?? 0
        self.outputAudioTokens = (try? container.decode(Int.self, forKey: .outputAudioTokens)) ?? 0
        self.requestCount = (try? container.decode(Int.self, forKey: .requestCount)) ?? 0
    }
}

struct CompletionUsageTotal {
    let inputTokens: Int
    let outputTokens: Int
    let requestCount: Int
}

struct OpenAICostsResponse: Decodable {
    let data: [CostBucket]

    var total: Double {
        data.reduce(0) { partial, bucket in
            partial + bucket.results.reduce(0) { $0 + ($1.amount?.value ?? 0) }
        }
    }
}

struct CostBucket: Decodable {
    let results: [CostResult]
}

struct CostResult: Decodable {
    let amount: CostAmount?
}

struct CostAmount: Decodable {
    let value: Double?
}

enum TokenUsageError: LocalizedError {
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status, let message):
            if let message, !message.isEmpty {
                return "OpenAI API HTTP \(status): \(message)"
            }
            return "OpenAI API HTTP \(status)"
        }
    }
}

struct WidgetOpenAIErrorResponse: Decodable {
    let error: WidgetOpenAIErrorDetail?

    static func message(from data: Data) -> String? {
        (try? JSONDecoder().decode(WidgetOpenAIErrorResponse.self, from: data))?.error?.message
    }
}

struct WidgetOpenAIErrorDetail: Decodable {
    let message: String?
}
