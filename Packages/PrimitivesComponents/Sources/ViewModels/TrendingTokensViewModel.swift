// Copyright (c). Gem Wallet. All rights reserved.

import Foundation
import SwiftUI
import Combine
import Primitives

// MARK: - Enums (shared)

public enum TrendingSortOption: String, CaseIterable, Identifiable {
    case rank = "Rank"
    case volume = "Volume"
    case liquidity = "Liquidity"

    public var id: String { rawValue }
    public var displayText: String { rawValue }
    public var apiValue: String {
        switch self {
        case .rank: return "rank"
        case .volume: return "volume24hUSD"
        case .liquidity: return "liquidity"
        }
    }
}

public enum TrendingNetwork: String, CaseIterable, Identifiable {
    case solana = "solana"
    case ethereum = "ethereum"
    case arbitrum = "arbitrum"
    case avalanche = "avalanche"
    case bsc = "bsc"
    case optimism = "optimism"
    case polygon = "polygon"
    case base = "base"

    public var id: String { rawValue }
    public var displayText: String {
        switch self {
        case .solana: return "Solana"
        case .ethereum: return "Ethereum"
        case .arbitrum: return "Arbitrum"
        case .avalanche: return "Avalanche"
        case .bsc: return "BSC"
        case .optimism: return "Optimism"
        case .polygon: return "Polygon"
        case .base: return "Base"
        }
    }

    public var apiValue: String { rawValue }
}

// MARK: - Models

public struct TrendingToken: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let symbol: String
    public let image: String
    public let currentPrice: Double
    public let priceChangePercentage24h: Double?
    public let marketCapRank: Int?
    public let sparklineIn7d: SparklineData?
    public let contractAddress: String?
    public let chain: Chain?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case symbol
        case image
        case currentPrice = "current_price"
        case priceChangePercentage24h = "price_change_percentage_24h"
        case marketCapRank = "market_cap_rank"
        case sparklineIn7d = "sparkline_in_7d"
        case contractAddress
        case chain
    }
}

public struct SparklineData: Codable, Sendable {
    public let price: [Double]
}

public struct NewListingToken: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let symbol: String
    public let logoURI: String?
    public let liquidity: Double?
    public let source: String?
    public let liquidityAddedAtISO8601: String?
    public let decimals: Int?
    public let chain: Chain?
}

// MARK: - ViewModel

@MainActor
public final class TrendingTokensViewModel: ObservableObject {

    private let repository = MarketDataRepository.shared
    private var cancellables = Set<AnyCancellable>()

    // Independent state for each section
    @Published public private(set) var currentTrendingChain: String
    @Published public private(set) var currentTrendingSortBy: String
    @Published public private(set) var currentTrendingSortType: String

    @Published public private(set) var currentNewListingsChain: String
    @Published public private(set) var currentNewListingsLimit: Int = 10
    @Published public private(set) var currentMemePlatformEnabled: Bool = false

    // Expose repository data (read by current section state)
    public var trendingTokens: [TrendingToken] {
        repository.trendingTokens[currentTrendingChain] ?? []
    }

    public var newListingTokens: [NewListingToken] {
        repository.newListingTokens[currentNewListingsChain] ?? []
    }

    // Loading / errors per section
    public var isLoadingTrending: Bool {
        repository.isLoadingTrending[currentTrendingChain] ?? false
    }

    public var isLoadingNewListings: Bool {
        repository.isLoadingNewListings[currentNewListingsChain] ?? false
    }

    public var trendingErrorMessage: String? {
        repository.errorMessages[currentTrendingChain]
    }

    public var newListingsErrorMessage: String? {
        repository.errorMessages[currentNewListingsChain]
    }

    public init() {
        // Seed from repo selection so everything starts aligned
        self.currentTrendingChain = repository.selectedChain
        self.currentTrendingSortBy = repository.sortBy
        self.currentTrendingSortType = repository.sortType

        self.currentNewListingsChain = repository.selectedNewListingsChain

        // Keep VM state in sync if some other screen updates the repo selection
        repository.$selectedChain
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.currentTrendingChain = $0 }
            .store(in: &cancellables)

        repository.$sortBy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.currentTrendingSortBy = $0 }
            .store(in: &cancellables)

        repository.$sortType
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.currentTrendingSortType = $0 }
            .store(in: &cancellables)

        repository.$selectedNewListingsChain
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.currentNewListingsChain = $0 }
            .store(in: &cancellables)

        // Relay repo data and flags to views
        [
            repository.$trendingTokens.map { _ in () }.eraseToAnyPublisher(),
            repository.$newListingTokens.map { _ in () }.eraseToAnyPublisher(),
            repository.$isLoadingTrending.map { _ in () }.eraseToAnyPublisher(),
            repository.$isLoadingNewListings.map { _ in () }.eraseToAnyPublisher(),
            repository.$errorMessages.map { _ in () }.eraseToAnyPublisher()
        ].forEach { pub in
            pub
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        // Initial fetch for Trending only
        Task {
            await repository.fetchTrendingIfNeeded(
                chain: currentTrendingChain,
                sortBy: currentTrendingSortBy,
                sortType: currentTrendingSortType,
                force: false
            )
        }
    }

    // MARK: - Actions

    public func refreshTrending(
        chain: String,
        sortBy: String,
        sortType: String
    ) async {
        // Update local state
        currentTrendingChain = chain
        currentTrendingSortBy = sortBy
        currentTrendingSortType = sortType

        // Also write selection to repo
        repository.selectedChain = chain
        repository.sortBy = sortBy
        repository.sortType = sortType

        await repository.fetchTrendingIfNeeded(
            chain: chain,
            sortBy: sortBy,
            sortType: sortType,
            force: false
        )
    }

    public func refreshNewListings(
        chain: String,
        limit: Int = 10,
        memePlatformEnabled: Bool = false
    ) async {
        // Update local state
        currentNewListingsChain = chain
        currentNewListingsLimit = limit
        currentMemePlatformEnabled = memePlatformEnabled

        // Also write selection to repo
        repository.selectedNewListingsChain = chain

        await repository.fetchNewListingsIfNeeded(
            chain: chain,
            limit: limit,
            memePlatformEnabled: memePlatformEnabled,
            force: false
        )
    }

    // MARK: - Formatting helpers

    public func formattedPrice(_ price: Double) -> String {
        if price >= 1 {
            return String(format: "$%.2f", price)
        } else if price >= 0.01 {
            return String(format: "$%.4f", price)
        } else {
            return String(format: "$%.6f", price)
        }
    }

    public func formattedPercentage(_ p: Double?) -> String {
        guard let p else { return "0.0%" }
        return String(format: "%.1f%%", p)
    }
}
