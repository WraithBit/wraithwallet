// Copyright (c). Gem Wallet. All rights reserved.

import SwiftUI
import Components
import Primitives
import Style
import Localization

public struct TrendingTokensSection: View {
    // Shared VM injected from WalletScene → WalletNavigationStack → MainTabView
    @ObservedObject public var viewModel: TrendingTokensViewModel

    // 🔁 Observe the repo so subtitle text updates live
    @ObservedObject private var repo = MarketDataRepository.shared

    // Match WalletScene usage
    let walletAssets: [AssetData]
    let onNavigateToAsset: (Asset) -> Void
    let onAddToken: (TrendingToken) async -> Asset?

    // Local UI state
    @State private var isAddingToken = false
    @State private var addingTokenName: String?
    @State private var isExpanded = true

    public init(
        viewModel: TrendingTokensViewModel,
        walletAssets: [AssetData],
        onNavigateToAsset: @escaping (Asset) -> Void,
        onAddToken: @escaping (TrendingToken) async -> Asset?
    ) {
        self.viewModel = viewModel
        self.walletAssets = walletAssets
        self.onNavigateToAsset = onNavigateToAsset
        self.onAddToken = onAddToken
    }

    // MARK: - Helpers

    private var subtitleText: String {
        let chain = repo.selectedChain.capitalized
        let sort: String
        switch repo.sortBy {
        case "rank": sort = "Rank"
        case "volume24hUSD": sort = "Volume"
        case "liquidity": sort = "Liquidity"
        default: sort = repo.sortBy.capitalized
        }
        return "\(chain) • \(sort)"
    }

    private func currentNetworkFromRepo() -> TrendingNetwork {
        TrendingNetwork(rawValue: repo.selectedChain) ?? .solana
    }

    private func currentSortFromRepo() -> TrendingSortOption {
        switch repo.sortBy {
        case "rank": return .rank
        case "liquidity": return .liquidity
        default: return .volume // "volume24hUSD"
        }
    }

    // MARK: - Body

    public var body: some View {
        Section {
            VStack(spacing: 0) {
                // HEADER — centered title/subtitle, trailing controls right-aligned
                ZStack {
                    VStack(spacing: 4) {
                        Text("Quick swap")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)

                        // 🔁 This now updates as repo changes
                        Text(subtitleText)
                            .font(.system(size: 12))
                            .foregroundColor(Colors.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    HStack(spacing: 12) {
                        Spacer()
                        NavigationLink {
                            TrendingTokensFullView(
                                viewModel: viewModel,
                                walletAssets: walletAssets,
                                onNavigateToAsset: onNavigateToAsset,
                                onAddToken: onAddToken,
                                // 🔁 Initialize with current repo selection
                                sortBy: currentSortFromRepo(),
                                selectedNetwork: currentNetworkFromRepo()
                            )
                        } label: {
                            Text("View all")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Colors.blue)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation { isExpanded.toggle() }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .foregroundColor(Colors.gray)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Spacing.medium)
                }
                .padding(.vertical, Spacing.medium)
                .background(Color(UIColor.secondarySystemBackground))

                // BODY
                if isExpanded {
                    Group {
                        if viewModel.isLoadingTrending && viewModel.trendingTokens.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(0..<3, id: \.self) { _ in
                                    ListItemLoadingView()
                                        .padding(.horizontal, Spacing.medium)
                                        .padding(.vertical, Spacing.small)
                                    Divider().padding(.leading, 60)
                                }
                            }
                        } else if viewModel.trendingTokens.isEmpty {
                            VStack(spacing: Spacing.medium) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 28))
                                    .foregroundColor(Colors.gray)
                                Text("No trending tokens available")
                                    .font(.system(size: 13))
                                    .foregroundColor(Colors.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.large)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(viewModel.trendingTokens.prefix(10).enumerated()), id: \.offset) { index, token in
                                    HomeTrendingTokenRow(
                                        rank: index + 1,
                                        token: token,
                                        onTap: { Task { await handleTokenTap(token) } }
                                    )
                                    if index < min(9, viewModel.trendingTokens.count - 1) {
                                        Divider().padding(.leading, 60)
                                    }
                                }
                            }
                        }
                    }
                    .background(Color(UIColor.secondarySystemBackground))
                }
            }
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .overlay {
                if isAddingToken, let tokenName = addingTokenName {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: .medium) {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                            Text("Adding \(tokenName)...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.large)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.8))
                        )
                    }
                }
            }
        } header: {
            EmptyView()
        }
        .task {
            if viewModel.trendingTokens.isEmpty {
                await viewModel.refreshTrending(chain: repo.selectedChain,
                                                sortBy: repo.sortBy,
                                                sortType: repo.sortType)
            }
        }
        .refreshable {
            await viewModel.refreshTrending(chain: repo.selectedChain,
                                            sortBy: repo.sortBy,
                                            sortType: repo.sortType)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Actions

    private func handleTokenTap(_ token: TrendingToken) async {
        if let existingAsset = findExistingAsset(for: token) {
            onNavigateToAsset(existingAsset)
            return
        }

        await MainActor.run {
            isAddingToken = true
            addingTokenName = token.name
        }

        if let newAsset = await onAddToken(token) {
            await MainActor.run {
                isAddingToken = false
                addingTokenName = nil
                onNavigateToAsset(newAsset)
            }
        } else {
            await MainActor.run {
                isAddingToken = false
                addingTokenName = nil
            }
        }
    }

    private func findExistingAsset(for token: TrendingToken) -> Asset? {
        if let contract = token.contractAddress {
            if let assetData = walletAssets.first(where: {
                $0.asset.id.tokenId?.lowercased() == contract.lowercased() &&
                $0.asset.id.chain == token.chain
            }) {
                return assetData.asset
            }
        }
        if let chain = token.chain,
           let assetData = walletAssets.first(where: {
               $0.asset.symbol.lowercased() == token.symbol.lowercased() &&
               $0.asset.id.chain == chain
           }) {
            return assetData.asset
        }
        return nil
    }
}

// MARK: - Compact row

private struct HomeTrendingTokenRow: View {
    let rank: Int
    let token: TrendingToken
    let onTap: () -> Void

    private var priceChangeColor: Color {
        guard let change = token.priceChangePercentage24h else { return Colors.gray }
        return change >= 0 ? Colors.green : Colors.red
    }

    private var formattedPrice: String {
        if token.currentPrice >= 1 {
            return String(format: "$%.2f", token.currentPrice)
        } else if token.currentPrice >= 0.01 {
            return String(format: "$%.4f", token.currentPrice)
        } else {
            return String(format: "$%.8f", token.currentPrice)
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.caption)
                    .foregroundColor(Colors.gray)
                    .frame(width: 24, alignment: .leading)

                AsyncImage(url: URL(string: token.image)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 32, height: 32)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(token.symbol.uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(token.name)
                        .font(.system(size: 12))
                        .foregroundColor(Colors.gray)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedPrice)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    if let change = token.priceChangePercentage24h {
                        Text("\(change >= 0 ? "+" : "")\(String(format: "%.2f", change))%")
                            .font(.caption)
                            .foregroundColor(priceChangeColor)
                    } else {
                        Text("--")
                            .font(.caption)
                            .foregroundColor(Colors.gray)
                    }
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(UIColor.secondarySystemBackground))
    }
}
