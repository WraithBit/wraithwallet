// TrendingTokensFullView.swift
// Copyright (c). Gem Wallet.

import SwiftUI
import Components
import Primitives
import Style
import Localization

public struct TrendingTokensFullView: View {
    @ObservedObject private var viewModel: TrendingTokensViewModel
    @ObservedObject private var repo = MarketDataRepository.shared
    @Environment(\.dismiss) private var dismiss

    // Parity with section: work via callbacks only
    let walletAssets: [AssetData]
    let onNavigateToAsset: (Asset) -> Void
    let onAddToken: (TrendingToken) async -> Asset?

    // Filter state
    @State var sortBy: TrendingSortOption
    @State var selectedNetwork: TrendingNetwork
    @State private var showFilterSheet = false

    // HUD state to match section UX
    @State private var isAddingToken = false
    @State private var addingTokenName: String?

    public init(
        viewModel: TrendingTokensViewModel,
        walletAssets: [AssetData],
        onNavigateToAsset: @escaping (Asset) -> Void,
        onAddToken: @escaping (TrendingToken) async -> Asset?,
        sortBy: TrendingSortOption = .rank,
        selectedNetwork: TrendingNetwork = .solana
    ) {
        self._viewModel = ObservedObject(initialValue: viewModel)
        self.walletAssets = walletAssets
        self.onNavigateToAsset = onNavigateToAsset
        self.onAddToken = onAddToken
        self._sortBy = State(initialValue: sortBy)
        self._selectedNetwork = State(initialValue: selectedNetwork)
    }

    public var body: some View {
        NavigationView {
            ZStack {
                List {
                    // Subtitle row (current filters + Filter button)
                    Section {
                        HStack {
                            Text("\(selectedNetwork.displayText) • \(sortBy.displayText)")
                                .font(.system(size: 14))
                                .foregroundColor(Colors.gray)
                            Spacer()
                            Button {
                                showFilterSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "line.3.horizontal.decrease")
                                    Text("Filter")
                                }
                                .font(.system(size: 14))
                                .foregroundColor(Colors.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(Color.clear)
                    }

                    ForEach(Array(viewModel.trendingTokens.enumerated()), id: \.element.id) { index, token in
                        Button {
                            Task { await handleTokenTap(token) }
                        } label: {
                            TrendingTokenRow(token: token, rank: index + 1)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(.assetListRowInsets)
                    }
                }
                .listSectionSpacing(.compact)
                .navigationTitle("Quick swap")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(Localized.Common.done) {
                            dismiss()
                        }
                    }
                }
                .refreshable { await refreshTrendingTokens() }
                .sheet(isPresented: $showFilterSheet) {
                    TrendingFilterSheet(
                        sortBy: $sortBy,
                        selectedNetwork: $selectedNetwork,
                        isPresented: $showFilterSheet,
                        onApply: { Task { await refreshTrendingTokens() } }
                    )
                }
                .onAppear {
                    // Sync with global repo like the section init does
                    if let net = TrendingNetwork(rawValue: repo.selectedChain) {
                        selectedNetwork = net
                    }
                    switch repo.sortBy {
                    case "rank": sortBy = .rank
                    case "liquidity": sortBy = .liquidity
                    default:      sortBy = .volume
                    }
                    Task { await refreshTrendingTokens() }
                }

                // Parity HUD with section
                if isAddingToken, let name = addingTokenName {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: Spacing.small) {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                            Text("Adding \(name)...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.large)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.85))
                        )
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Fetch

    private func refreshTrendingTokens() async {
        // Birdeye convention: rank -> asc, others -> desc
        let sortType = (sortBy == .rank) ? "asc" : "desc"

        // Update the global selection so other subtitles follow
        repo.selectedChain = selectedNetwork.apiValue
        repo.sortBy = sortBy.apiValue
        repo.sortType = sortType

        await viewModel.refreshTrending(
            chain: selectedNetwork.apiValue,
            sortBy: sortBy.apiValue,
            sortType: sortType
        )
    }

    // MARK: - Tap handling (identical flow to section)

    private func handleTokenTap(_ token: TrendingToken) async {
        if let existing = findExistingAsset(for: token) {
            onNavigateToAsset(existing)
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

// MARK: - Rows and filter sheet remain unchanged below

struct TrendingTokenRow: View {
    let token: TrendingToken
    let rank: Int

    var body: some View {
        HStack(spacing: .medium) {
            Text("#\(rank)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Colors.gray)
                .frame(width: 30, alignment: .leading)

            AsyncImageView(
                url: URL(string: token.image),
                placeholder: {
                    Circle()
                        .fill(Colors.grayVeryLight)
                        .frame(width: 32, height: 32)
                },
                image: { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                }
            )

            VStack(alignment: .leading, spacing: .extraSmall) {
                Text(token.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(token.symbol.uppercased())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Colors.gray)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: .extraSmall) {
                Text("$\(formattedPrice)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let change = token.priceChangePercentage24h {
                    HStack(spacing: .extraSmall) {
                        Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(abs(change), specifier: "%.1f")%")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(change >= 0 ? Colors.green : Colors.red)
                }
            }
        }
        .padding(.vertical, .extraSmall)
    }

    private var formattedPrice: String {
        if token.currentPrice >= 1 {
            return String(format: "%.2f", token.currentPrice)
        } else if token.currentPrice >= 0.01 {
            return String(format: "%.4f", token.currentPrice)
        } else {
            return String(format: "%.6f", token.currentPrice)
        }
    }
}

private struct AsyncImageView<Placeholder: View, ImageView: View>: View {
    let url: URL?
    let placeholder: () -> Placeholder
    let image: (Image) -> ImageView

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let loadedImage):
                image(loadedImage)
            case .failure(_), .empty:
                placeholder()
            @unknown default:
                placeholder()
            }
        }
    }
}

struct TrendingFilterSheet: View {
    @Binding var sortBy: TrendingSortOption
    @Binding var selectedNetwork: TrendingNetwork
    @Binding var isPresented: Bool
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Network") {
                    ForEach(TrendingNetwork.allCases) { network in
                        Button {
                            selectedNetwork = network
                        } label: {
                            HStack {
                                Text(network.displayText).foregroundColor(.primary)
                                Spacer()
                                if selectedNetwork == network {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Sort by") {
                    ForEach(TrendingSortOption.allCases) { option in
                        Button {
                            sortBy = option
                        } label: {
                            HStack {
                                Text(option.displayText).foregroundColor(.primary)
                                Spacer()
                                if sortBy == option {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Filter Trending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        onApply()
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
