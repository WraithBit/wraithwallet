// Copyright (c). Gem Wallet. All rights reserved.

import Foundation
import SwiftUI
import Primitives

// MARK: - Cache Models

struct CacheKey: Hashable, Codable {
    let endpoint: String // "trending" or "newListings"
    let chain: String
    let sortBy: String?
    let sortType: String?
}

struct CachedValue<T: Codable>: Codable {
    let data: T
    let fetchedAt: Date

    func isValid(ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(fetchedAt) < ttl
    }
}

// MARK: - Supporting Types

enum APIError: Error {
    case rateLimited
    case invalidResponse(String)
}

struct TrendingResponse: Codable {
    let tokens: [TrendingToken]
}

struct NewListingsResponse: Codable {
    let tokens: [NewListingToken]
}

// MARK: - Birdeye Response Models

private struct BirdeyeTrendingResponse: Codable {
    let data: BirdeyeTrendingData?
    let success: Bool
    let message: String?
}

private struct BirdeyeTrendingData: Codable {
    let tokens: [BirdeyeTrendingToken]
    let total: Int
}

private struct BirdeyeTrendingToken: Codable {
    let address: String
    let decimals: Int?
    let liquidity: Double?
    let logoURI: String?
    let marketcap: Double?
    let name: String
    let symbol: String
    let price: Double
    let price24hChangePercent: Double?
    let rank: Int?
}

private struct BirdeyeNewListingsResponse: Codable {
    let data: BirdeyeNewListingsData?
    let success: Bool
    let message: String?
}

private struct BirdeyeNewListingsData: Codable {
    let items: [BirdeyeNewListingToken]
    let total: Int?
}

private struct BirdeyeNewListingToken: Codable {
    let address: String
    let decimals: Int?
    let logoURI: String?
    let name: String
    let symbol: String
    let createdAt: String?
    let volume24h: Double?
    let price: Double?
    let price24hChangePercent: Double?
}

// MARK: - MarketDataRepository

@MainActor
public final class MarketDataRepository: ObservableObject {
    public static let shared = MarketDataRepository()

    // Published data keyed by chain (chain string -> array)
    @Published public var trendingTokens: [String: [TrendingToken]] = [:]
    @Published public var newListingTokens: [String: [NewListingToken]] = [:]
    @Published public var isLoadingTrending: [String: Bool] = [:]
    @Published public var isLoadingNewListings: [String: Bool] = [:]
    @Published public var errorMessages: [String: String] = [:]

    // Current selection (used by UI to seed filters)
    @Published public var selectedChain: String = "solana" { didSet { persistSelectionState() } }
    @Published public var sortBy: String = "rank" { didSet { persistSelectionState() } }
    @Published public var sortType: String = "asc" { didSet { persistSelectionState() } }
    @Published public var selectedNewListingsChain: String = "solana" { didSet { persistSelectionState() } }

    // Cache configuration
    private let trendingTTL: TimeInterval = 1200 // 20 minutes
    private let newListingsTTL: TimeInterval = 1200 // 20 minutes

    // Prevent duplicate requests
    private var inflightTrending: [CacheKey: Task<Void, Never>] = [:]
    private var inflightNewListings: [CacheKey: Task<Void, Never>] = [:]

    // Simple global rate limiting
    private var lastAPICallTime: Date?
    private let minTimeBetweenCalls: TimeInterval = 2.0

    // Birdeye API configuration
    private let baseURL = "https://public-api.birdeye.so"

    /// Reads BIRDEYE_API_KEY from Secrets.plist in the current target bundle.
    /// Add Secrets.plist to the target membership (App, and Widget only if the widget makes Birdeye calls).
    private var apiKey: String {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dict = plist as? [String: Any],
            let key = dict["BIRDEYE_API_KEY"] as? String
        else {
            assertionFailure("Missing Secrets.plist or BIRDEYE_API_KEY. Create Secrets.plist in this target and add BIRDEYE_API_KEY.")
            return ""
        }

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            assertionFailure("BIRDEYE_API_KEY is empty in Secrets.plist.")
        }
        return trimmed
    }

    // Timers for polling
    fileprivate var trendingTimer: Timer?
    fileprivate var newListingsTimer: Timer?

    // Selection persistence keys
    private let selChainKey = "mdr.sel.selectedChain"
    private let selSortByKey = "mdr.sel.sortBy"
    private let selSortTypeKey = "mdr.sel.sortType"
    private let selNewListingsChainKey = "mdr.sel.selectedNewListingsChain"

    private init() {
        loadSelectionState()      // restore selections first
        loadAllCachedData()       // then hydrate cached token data
    }

    // MARK: - Public Methods

    public func fetchTrendingIfNeeded(
        chain: String,
        sortBy: String = "rank",
        sortType: String = "asc",
        force: Bool = false
    ) async {
        let key = CacheKey(endpoint: "trending", chain: chain, sortBy: sortBy, sortType: sortType)

        if !force,
           let cached = loadFromDisk(TrendingResponse.self, key: key),
           cached.isValid(ttl: trendingTTL) {
            self.trendingTokens[chain] = cached.data.tokens
            return
        }

        if let task = inflightTrending[key] {
            await task.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetchTrendingTokens(chain: chain, sortBy: sortBy, sortType: sortType)
        }

        inflightTrending[key] = task
        defer { inflightTrending[key] = nil }
        await task.value
    }

    public func fetchNewListingsIfNeeded(
        chain: String,
        limit: Int = 10,
        memePlatformEnabled: Bool = false,
        force: Bool = false
    ) async {
        // Broadcast selection so UI can observe it
        self.selectedNewListingsChain = chain

        let key = CacheKey(
            endpoint: "newListings",
            chain: chain,
            sortBy: "\(limit)",
            sortType: memePlatformEnabled ? "meme" : "normal"
        )

        if !force,
           let cached = loadFromDisk(NewListingsResponse.self, key: key),
           cached.isValid(ttl: newListingsTTL) {
            self.newListingTokens[chain] = cached.data.tokens
            return
        }

        if let task = inflightNewListings[key] {
            await task.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetchNewListings(chain: chain, limit: limit, memePlatformEnabled: memePlatformEnabled)
        }

        inflightNewListings[key] = task
        defer { inflightNewListings[key] = nil }
        await task.value
    }

    // Starts BOTH timers (kept, but force=false to reduce API usage)
    public func startPollingForActiveChain() {
        stopPolling()

        trendingTimer = Timer.scheduledTimer(withTimeInterval: trendingTTL, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.fetchTrendingIfNeeded(
                    chain: self.selectedChain,
                    sortBy: self.sortBy,
                    sortType: self.sortType,
                    force: false
                )
            }
        }

        newListingsTimer = Timer.scheduledTimer(withTimeInterval: newListingsTTL, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.fetchNewListingsIfNeeded(
                    chain: self.selectedNewListingsChain,
                    force: false
                )
            }
        }
    }

    public func stopPolling() {
        trendingTimer?.invalidate(); trendingTimer = nil
        newListingsTimer?.invalidate(); newListingsTimer = nil
    }

    public func switchChain(to newChain: String) {
        selectedChain = newChain
        Task {
            await fetchTrendingIfNeeded(chain: newChain, sortBy: self.sortBy, sortType: self.sortType)
        }
    }

    // MARK: - Private Helpers

    private func mapChain(_ s: String?) -> Chain? {
        switch (s ?? "").lowercased() {
        case "solana", "sol": return .solana
        case "ethereum", "eth": return .ethereum
        case "arbitrum", "arb": return .arbitrum
        case "avalanche", "avax", "avalanchec": return .avalancheC
        case "bsc", "binance-smart-chain", "smartchain": return .smartChain
        case "optimism", "op": return .optimism
        case "polygon", "matic": return .polygon
        case "base": return .base
        default: return nil
        }
    }

    private func throttleIfNeeded() async {
        if let last = lastAPICallTime {
            let delta = Date().timeIntervalSince(last)
            if delta < minTimeBetweenCalls {
                let wait = minTimeBetweenCalls - delta
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        lastAPICallTime = Date()
    }

    // MARK: - Private Fetch Methods

    private func fetchTrendingTokens(
        chain: String,
        sortBy: String,
        sortType: String
    ) async {
        await throttleIfNeeded()

        isLoadingTrending[chain] = true
        errorMessages[chain] = nil

        do {
            var components = URLComponents(string: "\(baseURL)/defi/token_trending")!
            components.queryItems = [
                URLQueryItem(name: "sort_by", value: sortBy),
                URLQueryItem(name: "sort_type", value: sortType),
                URLQueryItem(name: "offset", value: "0"),
                URLQueryItem(name: "limit", value: "20")
            ]

            guard let url = components.url else { throw URLError(.badURL) }

            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(chain, forHTTPHeaderField: "x-chain")

            let (data, resp) = try await URLSession.shared.data(for: req)

            if let http = resp as? HTTPURLResponse, (http.statusCode == 429 || http.statusCode == 503) {
                throw APIError.rateLimited
            }

            let decoded = try JSONDecoder().decode(BirdeyeTrendingResponse.self, from: data)
            guard decoded.success, let items = decoded.data?.tokens else {
                throw APIError.invalidResponse(decoded.message ?? "No data")
            }

            let tokens: [TrendingToken] = items.compactMap { t in
                guard !t.name.isEmpty, !t.symbol.isEmpty else { return nil }

                return TrendingToken(
                    id: t.address,
                    name: t.name,
                    symbol: t.symbol,
                    image: t.logoURI ?? "",
                    currentPrice: t.price,
                    priceChangePercentage24h: t.price24hChangePercent,
                    marketCapRank: t.rank,
                    sparklineIn7d: nil,
                    contractAddress: t.address,
                    chain: mapChain(chain)
                )
            }

            self.trendingTokens[chain] = tokens

            let key = CacheKey(endpoint: "trending", chain: chain, sortBy: sortBy, sortType: sortType)
            saveToDisk(TrendingResponse(tokens: tokens), key: key)
        } catch {
            handleError(error, for: chain)
        }

        isLoadingTrending[chain] = false
    }

    private func fetchNewListings(
        chain: String,
        limit: Int,
        memePlatformEnabled: Bool
    ) async {
        await throttleIfNeeded()

        isLoadingNewListings[chain] = true
        errorMessages[chain] = nil

        do {
            var components = URLComponents(string: "\(baseURL)/defi/v2/tokens/new_listing")!
            components.queryItems = [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "meme_platform_enabled", value: memePlatformEnabled ? "true" : "false")
            ]

            guard let url = components.url else { throw URLError(.badURL) }

            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(chain, forHTTPHeaderField: "x-chain")

            let (data, resp) = try await URLSession.shared.data(for: req)

            if let http = resp as? HTTPURLResponse, (http.statusCode == 429 || http.statusCode == 503) {
                throw APIError.rateLimited
            }

            let decoded = try JSONDecoder().decode(BirdeyeNewListingsResponse.self, from: data)
            guard decoded.success, let items = decoded.data?.items else {
                throw APIError.invalidResponse(decoded.message ?? "No data")
            }

            let listings: [NewListingToken] = items.compactMap { t in
                guard !t.name.isEmpty, !t.symbol.isEmpty else { return nil }
                return NewListingToken(
                    id: t.address,
                    name: t.name,
                    symbol: t.symbol,
                    logoURI: t.logoURI,
                    liquidity: t.volume24h,
                    source: "birdeye",
                    liquidityAddedAtISO8601: t.createdAt,
                    decimals: t.decimals,
                    chain: mapChain(chain)
                )
            }

            self.newListingTokens[chain] = listings

            let key = CacheKey(
                endpoint: "newListings",
                chain: chain,
                sortBy: "\(limit)",
                sortType: memePlatformEnabled ? "meme" : "normal"
            )
            saveToDisk(NewListingsResponse(tokens: listings), key: key)
        } catch {
            handleError(error, for: chain)
        }

        isLoadingNewListings[chain] = false
    }

    // MARK: - Disk Cache Methods

    private func saveToDisk<T: Codable>(_ data: T, key: CacheKey) {
        let cached = CachedValue(data: data, fetchedAt: Date())
        let url = getCacheURL(for: key)

        do {
            let encoded = try JSONEncoder().encode(cached)
            try encoded.write(to: url)
        } catch {
            print("Failed to save cache: \(error)")
        }
    }

    private func loadFromDisk<T: Codable>(_ type: T.Type, key: CacheKey) -> CachedValue<T>? {
        let url = getCacheURL(for: key)

        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedValue<T>.self, from: data) else {
            return nil
        }

        return cached
    }

    private func getCacheURL(for key: CacheKey) -> URL {
        let documentsPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let filename = "\(key.endpoint)_\(key.chain)_\(key.sortBy ?? "")_\(key.sortType ?? "").json"
        return documentsPath.appendingPathComponent(filename)
    }

    private func loadAllCachedData() {
        for chain in ["solana", "ethereum", "arbitrum", "base", "polygon", "optimism", "avalanche", "bsc"] {
            let trendingKey = CacheKey(endpoint: "trending", chain: chain, sortBy: "rank", sortType: "asc")
            if let cached = loadFromDisk(TrendingResponse.self, key: trendingKey),
               cached.isValid(ttl: trendingTTL) {
                self.trendingTokens[chain] = cached.data.tokens
            }

            let listingsKey = CacheKey(endpoint: "newListings", chain: chain, sortBy: "10", sortType: "normal")
            if let cached = loadFromDisk(NewListingsResponse.self, key: listingsKey),
               cached.isValid(ttl: newListingsTTL) {
                self.newListingTokens[chain] = cached.data.tokens
            }
        }
    }

    // MARK: - Selection persistence

    private func persistSelectionState() {
        let d = UserDefaults.standard
        d.set(selectedChain, forKey: selChainKey)
        d.set(sortBy, forKey: selSortByKey)
        d.set(sortType, forKey: selSortTypeKey)
        d.set(selectedNewListingsChain, forKey: selNewListingsChainKey)
    }

    private func loadSelectionState() {
        let d = UserDefaults.standard
        if let v = d.string(forKey: selChainKey) { selectedChain = v }
        if let v = d.string(forKey: selSortByKey) { sortBy = v }
        if let v = d.string(forKey: selSortTypeKey) { sortType = v }
        if let v = d.string(forKey: selNewListingsChainKey) { selectedNewListingsChain = v }
    }

    private func handleError(_ error: Error, for chain: String) {
        if let apiError = error as? APIError {
            switch apiError {
            case .rateLimited:
                errorMessages[chain] = "Rate limited. Try again later."
            case .invalidResponse(let message):
                errorMessages[chain] = message
            }
        } else {
            errorMessages[chain] = "Failed to load data"
        }
        print("Error for \(chain): \(error)")
    }
}
