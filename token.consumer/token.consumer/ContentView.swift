//
//  ContentView.swift
//  token.consumer
//
//  Created by Vitor Furini on 25/05/26.
//

import SwiftUI
import Foundation

struct ContentView: View {
    @AppStorage(SharedSettings.projectIDKey, store: SharedSettings.defaults) private var projectID = ""
    @AppStorage(SharedSettings.monthlyLimitKey, store: SharedSettings.defaults) private var monthlyLimit = 1000000
    @AppStorage(SharedSettings.monthlyBudgetUSDKey, store: SharedSettings.defaults) private var monthlyBudgetUSD = 0.0

    @State private var openAIAdminKey = ""
    @State private var usage = AppTokenUsageSnapshot.preview
    @State private var isLoading = false
    @State private var lastRefresh: Date?
    @State private var keychainMessage: String?
    @State private var notificationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image("TokenPulseLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("AI Token Usage")
                                .font(.title3.weight(.semibold))
                            Text("OpenAI usage monitor")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("OpenAI") {
                    SecureField("OpenAI Admin Key", text: $openAIAdminKey)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        saveAdminKey()
                    } label: {
                        Label("Save key", systemImage: "key")
                    }

                    if let keychainMessage {
                        Text(keychainMessage)
                            .font(.caption)
                            .foregroundStyle(keychainMessage.hasPrefix("Error") ? .red : .secondary)
                    }

                    TextField("Optional project ID", text: $projectID)
                        .textFieldStyle(.roundedBorder)

                    Stepper(value: $monthlyLimit, in: 1...1_000_000_000, step: 10_000) {
                        Text("Monthly reference: \(monthlyLimit.formatted()) tokens")
                    }

                    Stepper(value: $monthlyBudgetUSD, in: 0...1_000_000, step: 5) {
                        Text("Monthly budget: \(monthlyBudgetUSD, format: .currency(code: "USD"))")
                    }
                }

                Section("Alerts") {
                    Button {
                        Task { await requestNotificationAuthorization() }
                    } label: {
                        Label("Enable 50% notification", systemImage: "bell.badge")
                    }

                    if let notificationMessage {
                        Text(notificationMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Current month usage") {
                    HStack(alignment: .firstTextBaseline) {
                        Text(usage.primaryCostText)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("USD")
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: usage.budgetProgress)
                        .tint(usage.budgetProgress > 0.85 ? .red : .green)

                    if usage.monthlyBudgetUSD > 0 {
                        Text("\(Int((usage.budgetProgress * 100).rounded()))% of monthly budget")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        if let cost = usage.costUSD {
                            GridRow {
                                Text("Spend")
                                HStack(spacing: 4) {
                                    Text(cost, format: .currency(code: "USD"))
                                    if usage.monthlyBudgetUSD > 0 {
                                        Text("/ \(usage.monthlyBudgetUSD, format: .currency(code: "USD"))")
                                    }
                                }
                                .monospacedDigit()
                            }
                        }
                        GridRow {
                            Text("Tokens")
                            Text(usage.totalTokens.formatted())
                                .monospacedDigit()
                        }
                        GridRow {
                            Text("Requests")
                            Text(usage.requestCount.formatted())
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(.secondary)

                    if let errorMessage = usage.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }

                    if let costErrorMessage = usage.costErrorMessage {
                        Label(costErrorMessage, systemImage: "dollarsign.circle")
                            .foregroundStyle(.orange)
                    }

                    if let lastRefresh {
                        Text("Updated at \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("AI Token Usage")
            .toolbar {
                Button {
                    Task { await refreshUsage() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .frame(minWidth: 460, minHeight: 520)
        .onAppear {
            openAIAdminKey = KeychainStore.readAdminKey()
        }
        .task {
            await refreshUsage()
        }
    }

    private func saveAdminKey() {
        do {
            try KeychainStore.saveAdminKey(openAIAdminKey)
            keychainMessage = "Key saved for the app and widget."
        } catch {
            keychainMessage = "Error saving key: \(error.localizedDescription)"
        }
    }

    private func refreshUsage() async {
        isLoading = true
        usage = await AppTokenUsageClient.fetch(
            adminKey: KeychainStore.readAdminKey(),
            projectID: projectID,
            fallbackTokenLimit: monthlyLimit,
            fallbackBudgetUSD: monthlyBudgetUSD
        )
        UsageNotificationManager.notifyIfNeeded(
            totalTokens: usage.totalTokens,
            monthlyLimit: usage.monthlyLimit,
            costUSD: usage.costUSD,
            monthlyBudgetUSD: usage.monthlyBudgetUSD
        )
        lastRefresh = Date()
        isLoading = false
    }

    private func requestNotificationAuthorization() async {
        let allowed = await UsageNotificationManager.requestAuthorization()
        notificationMessage = allowed
            ? "Notification enabled. The alert will be sent when usage passes 50% this month."
            : "Permission denied. Enable notifications in System Settings."
    }
}

#Preview {
    ContentView()
}

struct AppTokenUsageSnapshot {
    var totalTokens: Int
    var inputTokens: Int
    var outputTokens: Int
    var requestCount: Int
    var monthlyLimit: Int
    var costUSD: Double?
    var monthlyBudgetUSD: Double
    var costErrorMessage: String?
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

    static let preview = AppTokenUsageSnapshot(
        totalTokens: 128420,
        inputTokens: 91200,
        outputTokens: 37220,
        requestCount: 84,
        monthlyLimit: 1000000,
        costUSD: 14.72,
        monthlyBudgetUSD: 50,
        costErrorMessage: nil,
        errorMessage: nil
    )

    static func failure(_ message: String, fallbackTokenLimit: Int, fallbackBudgetUSD: Double) -> AppTokenUsageSnapshot {
        AppTokenUsageSnapshot(
            totalTokens: 0,
            inputTokens: 0,
            outputTokens: 0,
            requestCount: 0,
            monthlyLimit: fallbackTokenLimit,
            costUSD: nil,
            monthlyBudgetUSD: fallbackBudgetUSD,
            costErrorMessage: nil,
            errorMessage: message
        )
    }

    init(totalTokens: Int, inputTokens: Int, outputTokens: Int, requestCount: Int, monthlyLimit: Int, costUSD: Double?, monthlyBudgetUSD: Double, costErrorMessage: String?, errorMessage: String?) {
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.requestCount = requestCount
        self.monthlyLimit = monthlyLimit
        self.costUSD = costUSD
        self.monthlyBudgetUSD = monthlyBudgetUSD
        self.costErrorMessage = costErrorMessage
        self.errorMessage = errorMessage
    }
}

enum AppTokenUsageClient {
    static func fetch(adminKey: String, projectID: String, fallbackTokenLimit: Int, fallbackBudgetUSD: Double) async -> AppTokenUsageSnapshot {
        guard !adminKey.isEmpty else {
            return .failure("Configure an OpenAI Admin Key.", fallbackTokenLimit: fallbackTokenLimit, fallbackBudgetUSD: fallbackBudgetUSD)
        }

        do {
            async let usageResponse = fetchCompletionUsage(adminKey: adminKey, projectID: projectID)
            async let costsResponse = fetchCosts(adminKey: adminKey, projectID: projectID)
            let usage = try await usageResponse
            let costResult: Result<Double, Error>
            do {
                costResult = .success(try await costsResponse)
            } catch {
                costResult = .failure(error)
            }
            let cost = try? costResult.get()

            return AppTokenUsageSnapshot(
                totalTokens: usage.inputTokens + usage.outputTokens,
                inputTokens: usage.inputTokens,
                outputTokens: usage.outputTokens,
                requestCount: usage.requestCount,
                monthlyLimit: fallbackTokenLimit,
                costUSD: cost,
                monthlyBudgetUSD: fallbackBudgetUSD,
                costErrorMessage: costResult.errorMessage(prefix: "Cost unavailable"),
                errorMessage: nil
            )
        } catch {
            return .failure(error.localizedDescription, fallbackTokenLimit: fallbackTokenLimit, fallbackBudgetUSD: fallbackBudgetUSD)
        }
    }

    private static func fetchCompletionUsage(adminKey: String, projectID: String) async throws -> AppCompletionUsageTotal {
        let startTime = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        var components = URLComponents(string: "https://api.openai.com/v1/organization/usage/completions")!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(Int(startTime.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31")
        ]
        if !projectID.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "project_ids", value: projectID))
        }

        let response: AppOpenAIUsageResponse = try await request(components.url!, adminKey: adminKey)
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
            components.queryItems?.append(URLQueryItem(name: "project_ids", value: projectID))
        }

        let response: AppOpenAICostsResponse = try await request(components.url!, adminKey: adminKey)
        return response.total
    }

    private static func request<Response: Decodable>(_ url: URL, adminKey: String) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(sanitizeAdminKey(adminKey))", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw AppTokenUsageError.httpStatus(httpResponse.statusCode, OpenAIErrorResponse.message(from: data))
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

struct AppOpenAIUsageResponse: Decodable {
    let data: [AppUsageBucket]

    var total: AppCompletionUsageTotal {
        data.reduce(AppCompletionUsageTotal(inputTokens: 0, outputTokens: 0, requestCount: 0)) { partial, bucket in
            let bucketTotal = bucket.results.reduce(AppCompletionUsageTotal(inputTokens: 0, outputTokens: 0, requestCount: 0)) { resultPartial, result in
                AppCompletionUsageTotal(
                    inputTokens: resultPartial.inputTokens + result.inputTokens + result.inputAudioTokens,
                    outputTokens: resultPartial.outputTokens + result.outputTokens + result.outputAudioTokens,
                    requestCount: resultPartial.requestCount + result.requestCount
                )
            }
            return AppCompletionUsageTotal(
                inputTokens: partial.inputTokens + bucketTotal.inputTokens,
                outputTokens: partial.outputTokens + bucketTotal.outputTokens,
                requestCount: partial.requestCount + bucketTotal.requestCount
            )
        }
    }
}

struct AppUsageBucket: Decodable {
    let results: [AppCompletionUsageResult]
}

struct AppCompletionUsageResult: Decodable {
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

struct AppCompletionUsageTotal {
    let inputTokens: Int
    let outputTokens: Int
    let requestCount: Int
}

struct AppOpenAICostsResponse: Decodable {
    let data: [AppCostBucket]

    var total: Double {
        data.reduce(0) { partial, bucket in
            partial + bucket.results.reduce(0) { $0 + ($1.amount?.value ?? 0) }
        }
    }
}

struct AppCostBucket: Decodable {
    let results: [AppCostResult]
}

struct AppCostResult: Decodable {
    let amount: AppCostAmount?
}

struct AppCostAmount: Decodable {
    let value: Double?
}

enum AppTokenUsageError: LocalizedError {
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

struct OpenAIErrorResponse: Decodable {
    let error: OpenAIErrorDetail?

    static func message(from data: Data) -> String? {
        (try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data))?.error?.message
    }
}

struct OpenAIErrorDetail: Decodable {
    let message: String?
}

private extension Result {
    func errorMessage(prefix: String) -> String? {
        if case .failure(let error) = self {
            return "\(prefix): \(error.localizedDescription)"
        }
        return nil
    }
}
