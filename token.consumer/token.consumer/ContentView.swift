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
                        Label("Salvar chave", systemImage: "key")
                    }

                    if let keychainMessage {
                        Text(keychainMessage)
                            .font(.caption)
                            .foregroundStyle(keychainMessage.hasPrefix("Erro") ? .red : .secondary)
                    }

                    TextField("Project ID opcional", text: $projectID)
                        .textFieldStyle(.roundedBorder)

                    Stepper(value: $monthlyLimit, in: 1...1_000_000_000, step: 10_000) {
                        Text("Referencia mensal: \(monthlyLimit.formatted()) tokens")
                    }

                    Stepper(value: $monthlyBudgetUSD, in: 0...1_000_000, step: 5) {
                        Text("Orcamento mensal: \(monthlyBudgetUSD, format: .currency(code: "USD"))")
                    }
                }

                Section("Alertas") {
                    Button {
                        Task { await requestNotificationAuthorization() }
                    } label: {
                        Label("Ativar notificacao em 50%", systemImage: "bell.badge")
                    }

                    if let notificationMessage {
                        Text(notificationMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Consumo do mes atual") {
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
                        Text("\(Int((usage.budgetProgress * 100).rounded()))% do orcamento mensal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        if let cost = usage.costUSD {
                            GridRow {
                                Text("Gasto")
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

                    if let lastRefresh {
                        Text("Atualizado as \(lastRefresh.formatted(date: .omitted, time: .shortened))")
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
                    Label("Atualizar", systemImage: "arrow.clockwise")
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
            keychainMessage = "Chave salva para o app e o widget."
        } catch {
            keychainMessage = "Erro ao salvar: \(error.localizedDescription)"
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
            ? "Notificacao ativada. O alerta sera enviado ao passar de 50% no mes."
            : "Permissao negada. Ative notificacoes em System Settings."
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
            errorMessage: message
        )
    }

    init(totalTokens: Int, inputTokens: Int, outputTokens: Int, requestCount: Int, monthlyLimit: Int, costUSD: Double?, monthlyBudgetUSD: Double, errorMessage: String?) {
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.requestCount = requestCount
        self.monthlyLimit = monthlyLimit
        self.costUSD = costUSD
        self.monthlyBudgetUSD = monthlyBudgetUSD
        self.errorMessage = errorMessage
    }
}

enum AppTokenUsageClient {
    static func fetch(adminKey: String, projectID: String, fallbackTokenLimit: Int, fallbackBudgetUSD: Double) async -> AppTokenUsageSnapshot {
        guard !adminKey.isEmpty else {
            return .failure("Configure uma OpenAI Admin Key.", fallbackTokenLimit: fallbackTokenLimit, fallbackBudgetUSD: fallbackBudgetUSD)
        }

        do {
            async let usageResponse = fetchCompletionUsage(adminKey: adminKey, projectID: projectID)
            async let costsResponse = fetchCosts(adminKey: adminKey, projectID: projectID)
            let usage = try await usageResponse
            let cost = try? await costsResponse

            return AppTokenUsageSnapshot(
                totalTokens: usage.inputTokens + usage.outputTokens,
                inputTokens: usage.inputTokens,
                outputTokens: usage.outputTokens,
                requestCount: usage.requestCount,
                monthlyLimit: fallbackTokenLimit,
                costUSD: cost,
                monthlyBudgetUSD: fallbackBudgetUSD,
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
            components.queryItems?.append(URLQueryItem(name: "project_ids[]", value: projectID))
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
            components.queryItems?.append(URLQueryItem(name: "project_ids[]", value: projectID))
        }

        let response: AppOpenAICostsResponse = try await request(components.url!, adminKey: adminKey)
        return response.total
    }

    private static func request<Response: Decodable>(_ url: URL, adminKey: String) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw AppTokenUsageError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(Response.self, from: data)
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
            partial + bucket.results.reduce(0) { $0 + $1.amount.value }
        }
    }
}

struct AppCostBucket: Decodable {
    let results: [AppCostResult]
}

struct AppCostResult: Decodable {
    let amount: AppCostAmount
}

struct AppCostAmount: Decodable {
    let value: Double
}

enum AppTokenUsageError: LocalizedError {
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            "OpenAI API HTTP \(status)"
        }
    }
}
