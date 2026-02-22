import SwiftUI
import Swap
import Primitives
import WalletsService
import SwapService
import Preferences
import Keystore
import PriceAlertService
import Assets
import AssetsService
import PrimitivesComponents
import Components
import Store
import UIKit

// MARK: - Theme Colors
extension Color {
    // Repoint Phantom purple to Wraith green
    // #0EC72E
    static let phantomPurple = Color(red: 14/255, green: 199/255, blue: 46/255)

    // Old-fork positive green #1B9A6C
    static let positiveGreen = Color(red: 27/255, green: 154/255, blue: 108/255)

    // Keep the same red used before (this wasn't part of Phantom's purple)
    static let negativeRed = Color(red: 255/255, green: 71/255, blue: 71/255)

    // Match the glow to the new brand green
    static let glowPurple = Color(red: 14/255, green: 199/255, blue: 46/255).opacity(0.3)
}

// MARK: - Haptic Manager
@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private init() {}

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}

public struct SwapNavigationStack: View {
    // MARK: - Inputs
    let wallet: Wallet
    let defaultAsset: Asset
    let swapQuotesProvider: any SwapQuotesProvidable
    let swapQuoteDataProvider: any SwapQuoteDataProvidable
    let priceAlertService: PriceAlertService
    let onOpenAsset: (Asset) -> Void
    let onSwapBuilt: (TransferData) -> Void

    // MARK: - Environment
    @Environment(\.walletsService) private var walletsService
    @Environment(\.assetsService) private var assetsService
    @Environment(\.activityService) private var activityService
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - State
    @State private var viewModel: SwapSceneViewModel?
    @State private var isTrendingExpanded = false
    @State private var isNewListingsExpanded = false
    @State private var showTrendingFilterSheet = false
    @State private var showNewListingsFilterSheet = false
    @State private var trendingSortBy: TrendingSortOption = .rank
    @State private var trendingNetwork: TrendingNetwork = .solana
    @State private var newListingsNetwork: TrendingNetwork = .solana
    @State private var newListingsLimit: Int = 10
    @State private var memePlatformEnabled: Bool = false
    @State private var rootSize: CGSize = .zero
    @State private var didAppearOnce = false
    @State private var didPrimeAccessory = false
    @State private var didNudgeOnce = false
    @State private var viewCycle: Int = 0

    @ObservedObject private var repo = MarketDataRepository.shared
    @ObservedObject private var trendingViewModel = TrendingTokensViewModel()

    // MARK: - Init
    public init(
        wallet: Wallet,
        defaultAsset: Asset,
        swapQuotesProvider: any SwapQuotesProvidable,
        swapQuoteDataProvider: any SwapQuoteDataProvidable,
        priceAlertService: PriceAlertService,
        onOpenAsset: @escaping (Asset) -> Void,
        onSwapBuilt: @escaping (TransferData) -> Void
    ) {
        self.wallet = wallet
        self.defaultAsset = defaultAsset
        self.swapQuotesProvider = swapQuotesProvider
        self.swapQuoteDataProvider = swapQuoteDataProvider
        self.priceAlertService = priceAlertService
        self.onOpenAsset = onOpenAsset
        self.onSwapBuilt = onSwapBuilt
    }

    // MARK: - Computed
    private var trendingSubtitle: String {
        let chain = trendingNetwork.displayText
        let sort: String
        switch trendingSortBy {
        case .rank: sort = "Trending"
        case .volume: sort = "Volume"
        case .liquidity: sort = "Liquidity"
        }
        return "\(chain) • \(sort)"
    }

    private var newListingsSubtitle: String {
        let base = newListingsNetwork.displayText
        let memeSuffix = (newListingsNetwork == .solana && memePlatformEnabled) ? " • Memes" : ""
        return base + memeSuffix
    }

    // MARK: - Body
    public var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                backgroundGradient

                // Single unified ScrollView for everything
                ScrollView {
                    VStack(spacing: 24) {
                        // Swap interface
                        Group {
                            if let vm = viewModel {
                                // IMPORTANT: embedded mode removes the inner List scrolling
                                SwapScene(model: vm, presentation: .embedded)
                                    .id(viewCycle)
                            } else {
                                ProgressView()
                                    .frame(height: 200)
                                    .onAppear(perform: buildViewModelIfNeeded)
                            }
                        }
                        .padding(.top, 8)

                        // Trending section
                        EnhancedTrendingSection(
                            tokens: trendingViewModel.trendingTokens,
                            isExpanded: $isTrendingExpanded,
                            subtitle: trendingSubtitle,
                            onTokenTap: handleTrendingTokenSelection,
                            onFilterTap: {
                                showTrendingFilterSheet = true
                                HapticManager.shared.impact(.light)
                            },
                            title: "Trending"
                        )

                        // New Listings section
                        EnhancedNewListingsSection(
                            items: trendingViewModel.newListingTokens,
                            isExpanded: $isNewListingsExpanded,
                            subtitle: newListingsSubtitle,
                            onItemTap: handleNewListingSelection,
                            onFilterTap: {
                                showNewListingsFilterSheet = true
                                HapticManager.shared.impact(.light)
                            },
                            title: "New Listings"
                        )
                    }
                    .padding(.bottom, 100)
                }

                // Geometry reader for size tracking - PRESERVED
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            rootSize = proxy.size
                            dlog("rootSize onAppear: \(format(proxy.size))")
                        }
                        .onChange(of: proxy.size) { _, newSize in
                            rootSize = newSize
                            dlog("rootSize changed: \(format(newSize))")
                        }
                }
                .allowsHitTesting(false)

                // Keyboard accessory primer - PRESERVED
                if !didPrimeAccessory && rootSize.width > 0 {
                    KeyboardAccessoryPrimer(
                        widthProvider: { rootSize.width },
                        onDone: { didPrimeAccessory = true }
                    )
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle("Swap")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                seedFromRepo()
                dlog("onAppear (didAppearOnce=\(didAppearOnce))")
                if didAppearOnce == false {
                    didAppearOnce = true
                }
            }
            .task {
                seedFromRepo()
                await refreshTrendingTokens()
                await refreshNewListingTokens()
            }
            .sheet(isPresented: $showTrendingFilterSheet) {
                TrendingFilterSheet(
                    sortBy: $trendingSortBy,
                    selectedNetwork: $trendingNetwork,
                    memePlatformEnabled: .constant(false),
                    isPresented: $showTrendingFilterSheet,
                    onApply: {
                        Task { await refreshTrendingTokens() }
                    }
                )
            }
            .sheet(isPresented: $showNewListingsFilterSheet) {
                NewListingsFilterSheet(
                    selectedNetwork: $newListingsNetwork,
                    memePlatformEnabled: $memePlatformEnabled,
                    limit: $newListingsLimit,
                    isPresented: $showNewListingsFilterSheet,
                    onApply: {
                        Task { await refreshNewListingTokens() }
                    }
                )
            }
            .sheet(item: Binding<SwapSheetType?>(
                get: { viewModel?.isPresentingInfoSheet },
                set: { viewModel?.isPresentingInfoSheet = $0 }
            )) { sheetType in
                switch sheetType {
                case .selectAsset(let type):
                    NavigationStack {
                        let searchSvc = AssetSearchService(assetsService: assetsService)
                        SelectAssetScene(
                            model: SelectAssetViewModel(
                                wallet: wallet,
                                selectType: mapSwapTypeToSelectType(type),
                                searchService: searchSvc,
                                walletsService: walletsService,
                                priceAlertService: priceAlertService,
                                activityService: activityService,
                                selectAssetAction: { asset in
                                    viewModel?.onFinishAssetSelection(asset: asset)
                                }
                            )
                        )
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Done") {
                                    viewModel?.isPresentingInfoSheet = nil
                                }
                            }
                        }
                    }

                case .swapDetails:
                    if let detailsVM = viewModel?.swapDetailsViewModel {
                        NavigationStack {
                            SwapDetailsView(model: Bindable(detailsVM))
                        }
                    } else {
                        EmptyView()
                    }

                case .info:
                    Text("Info").padding()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                dlog("keyboardWillShow")
                if !didNudgeOnce {
                    didNudgeOnce = true
                    DispatchQueue.main.async {
                        viewCycle += 1
                    }
                }
            }
        }
    }

    // MARK: - Background Gradient
    @ViewBuilder
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(UIColor.systemBackground),
                Color(UIColor.systemBackground).opacity(0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Private Methods (ALL PRESERVED)
    private func buildViewModelIfNeeded() {
        guard viewModel == nil else { return }

        let pairSelector = SwapPairSelectorViewModel(
            fromAssetId: defaultAsset.id,
            toAssetId: nil
        )

        let input = SwapInput(wallet: wallet, pairSelector: pairSelector)

        let vm = SwapSceneViewModel(
            input: input,
            walletsService: walletsService,
            swapQuotesProvider: swapQuotesProvider,
            swapQuoteDataProvider: swapQuoteDataProvider,
            onSwap: onSwapBuilt
        )

        viewModel = vm
    }

    private func seedFromRepo() {
        if let net = TrendingNetwork(rawValue: repo.selectedChain) {
            trendingNetwork = net
        }
        switch repo.sortBy {
        case "rank": trendingSortBy = .rank
        case "liquidity": trendingSortBy = .liquidity
        default: trendingSortBy = .volume
        }

        if let nlNet = TrendingNetwork(rawValue: repo.selectedNewListingsChain) {
            newListingsNetwork = nlNet
        }
    }

    private func refreshTrendingTokens() async {
        let sortType = (trendingSortBy == .rank) ? "asc" : "desc"

        if repo.selectedChain != trendingNetwork.apiValue {
            repo.selectedChain = trendingNetwork.apiValue
        }
        if repo.sortBy != trendingSortBy.apiValue {
            repo.sortBy = trendingSortBy.apiValue
        }
        if repo.sortType != sortType {
            repo.sortType = sortType
        }

        await trendingViewModel.refreshTrending(
            chain: trendingNetwork.apiValue,
            sortBy: trendingSortBy.apiValue,
            sortType: sortType
        )
    }

    private func refreshNewListingTokens() async {
        if repo.selectedNewListingsChain != newListingsNetwork.apiValue {
            repo.selectedNewListingsChain = newListingsNetwork.apiValue
        }

        await trendingViewModel.refreshNewListings(
            chain: newListingsNetwork.apiValue,
            limit: newListingsLimit,
            memePlatformEnabled: memePlatformEnabled && newListingsNetwork == .solana
        )
    }

    private func handleTrendingTokenSelection(_ token: TrendingToken) {
        HapticManager.shared.impact(.medium)

        guard let chain = token.chain,
              let contractAddress = token.contractAddress else {
            print("Missing chain or contract for \(token.symbol)")
            return
        }

        let assetId = AssetId(chain: chain, tokenId: contractAddress)
        let asset = Asset(
            id: assetId,
            name: token.name,
            symbol: token.symbol,
            decimals: getDecimalsForChain(chain),
            type: .token
        )

        Task {
            do {
                try assetsService.addNewAsset(walletId: wallet.walletId, asset: asset)
                await walletsService.enableAssets(walletId: wallet.walletId, assetIds: [asset.id], enabled: true)
            } catch {
                await walletsService.enableAssets(walletId: wallet.walletId, assetIds: [asset.id], enabled: true)
            }

            await MainActor.run {
                viewModel?.onFinishAssetSelection(asset: asset)
                onOpenAsset(asset)
            }
        }
    }

    private func handleNewListingSelection(_ item: NewListingToken) {
        HapticManager.shared.impact(.medium)

        guard let chain = item.chain else {
            print("Missing chain for new listing \(item.symbol)")
            return
        }

        let assetId = AssetId(chain: chain, tokenId: item.id)
        let asset = Asset(
            id: assetId,
            name: item.name,
            symbol: item.symbol,
            decimals: getDecimalsForChain(chain),
            type: .token
        )

        Task {
            do {
                try assetsService.addNewAsset(walletId: wallet.walletId, asset: asset)
                await walletsService.enableAssets(walletId: wallet.walletId, assetIds: [asset.id], enabled: true)
            } catch {
                await walletsService.enableAssets(walletId: wallet.walletId, assetIds: [asset.id], enabled: true)
            }

            await MainActor.run {
                viewModel?.onFinishAssetSelection(asset: asset)
                onOpenAsset(asset)
            }
        }
    }

    private func getDecimalsForChain(_ chain: Chain) -> Int32 {
        switch chain {
        case .solana: return 9
        case .ethereum, .arbitrum, .optimism, .polygon, .base, .zkSync,
             .smartChain, .avalancheC: return 18
        default: return 18
        }
    }

    private func mapSwapTypeToSelectType(_ swapType: SelectAssetSwapType) -> SelectAssetType {
        switch swapType {
        case .pay: return .swap(.pay)
        case .receive(let chains, let assetIds):
            return .swap(.receive(chains: chains, assetIds: assetIds))
        }
    }
}

// MARK: - Enhanced Trending Section
struct EnhancedTrendingSection: View {
    let tokens: [TrendingToken]
    @Binding var isExpanded: Bool
    let subtitle: String
    let onTokenTap: (TrendingToken) -> Void
    let onFilterTap: () -> Void
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
                HapticManager.shared.impact(.light)
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .tracking(0.5)

                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        Button(action: onFilterTap) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 14))
                                .foregroundColor(.phantomPurple)
                        }
                        .buttonStyle(.plain)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded && !tokens.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(tokens.prefix(10).enumerated()), id: \.offset) { index, token in
                        EnhancedTokenRow(
                            token: token,
                            rank: index + 1,
                            onTap: { onTokenTap(token) }
                        )

                        if index < min(9, tokens.count - 1) {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .padding(.horizontal)
    }
}

// MARK: - Enhanced Token Row
struct EnhancedTokenRow: View {
    let token: TrendingToken
    let rank: Int
    let onTap: () -> Void

    @State private var isPressed = false

    var priceChangeColor: Color {
        guard let change = token.priceChangePercentage24h else { return .gray }
        return change >= 0 ? .positiveGreen : .negativeRed
    }

    var formattedPrice: String {
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
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(rank <= 3 ? .phantomPurple : .secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(rank <= 3 ? Color.phantomPurple.opacity(0.1) : Color.clear)
                    )

                AsyncImage(url: URL(string: token.image)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.gray.opacity(0.2),
                                        Color.gray.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(token.symbol.uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(token.name)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedPrice)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)

                    if let change = token.priceChangePercentage24h {
                        HStack(spacing: 2) {
                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10))

                            Text("\(abs(change), specifier: "%.2f")%")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(priceChangeColor)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(isPressed ? Color.gray.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Enhanced New Listings Section
struct EnhancedNewListingsSection: View {
    let items: [NewListingToken]
    @Binding var isExpanded: Bool
    let subtitle: String
    let onItemTap: (NewListingToken) -> Void
    let onFilterTap: () -> Void
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
                HapticManager.shared.impact(.light)
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .tracking(0.5)

                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        Button(action: onFilterTap) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 14))
                                .foregroundColor(.phantomPurple)
                        }
                        .buttonStyle(.plain)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded && !items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(10).enumerated()), id: \.offset) { index, item in
                        EnhancedNewListingRow(
                            item: item,
                            rank: index + 1,
                            onTap: { onItemTap(item) }
                        )

                        if index < min(9, items.count - 1) {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .padding(.horizontal)
    }
}

// MARK: - Enhanced New Listing Row
struct EnhancedNewListingRow: View {
    let item: NewListingToken
    let rank: Int
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("NEW")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [ Color.phantomPurple, Color(red: 25/255, green: 164/255, blue: 48/255) ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )

                AsyncImage(url: URL(string: item.logoURI ?? "")) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.gray.opacity(0.2),
                                        Color.gray.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.symbol.uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(item.name)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let liq = item.liquidity {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Liquidity")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Text("$" + formatNumber(liq))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(isPressed ? Color.gray.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }

    private func formatNumber(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fK", v / 1_000) }
        return String(format: "%.0f", v)
    }
}

// MARK: - Filter Sheets
struct TrendingFilterSheet: View {
    @Binding var sortBy: TrendingSortOption
    @Binding var selectedNetwork: TrendingNetwork
    @Binding var memePlatformEnabled: Bool
    @Binding var isPresented: Bool
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Network") {
                    ForEach(TrendingNetwork.allCases) { network in
                        Button(action: {
                            selectedNetwork = network
                            HapticManager.shared.impact(.light)
                        }) {
                            HStack {
                                Text(network.displayText).foregroundColor(.primary)
                                Spacer()
                                if selectedNetwork == network {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.phantomPurple)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Sort by") {
                    ForEach(TrendingSortOption.allCases) { option in
                        Button(action: {
                            sortBy = option
                            HapticManager.shared.impact(.light)
                        }) {
                            HStack {
                                Text(option.displayText).foregroundColor(.primary)
                                Spacer()
                                if sortBy == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.phantomPurple)
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
                    Button("Cancel") {
                        isPresented = false
                        HapticManager.shared.impact(.light)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        onApply()
                        isPresented = false
                        HapticManager.shared.impact(.medium)
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.phantomPurple)
                }
            }
        }
    }
}

struct NewListingsFilterSheet: View {
    @Binding var selectedNetwork: TrendingNetwork
    @Binding var memePlatformEnabled: Bool
    @Binding var limit: Int
    @Binding var isPresented: Bool
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Network") {
                    ForEach(TrendingNetwork.allCases) { network in
                        Button(action: {
                            selectedNetwork = network
                            HapticManager.shared.impact(.light)
                        }) {
                            HStack {
                                Text(network.displayText).foregroundColor(.primary)
                                Spacer()
                                if selectedNetwork == network {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.phantomPurple)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if selectedNetwork == .solana {
                    Section("Options") {
                        Toggle("Include Meme Platforms", isOn: $memePlatformEnabled)
                            .tint(.phantomPurple)
                    }
                }

                Section("Limit") {
                    Picker("Items", selection: $limit) {
                        Text("10").tag(10)
                        Text("20").tag(20)
                        Text("50").tag(50)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Filter New Listings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                        HapticManager.shared.impact(.light)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        onApply()
                        isPresented = false
                        HapticManager.shared.impact(.medium)
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.phantomPurple)
                }
            }
        }
    }
}

// MARK: - Shimmer Modifier
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(0.2),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase * 200 - 100)
                .mask(content)
            )
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Keyboard Accessory Primer (PRESERVED)
private struct KeyboardAccessoryPrimer: UIViewRepresentable {
    let widthProvider: () -> CGFloat
    let onDone: () -> Void

    func makeUIView(context: Context) -> UIView {
        let host = UIView(frame: .zero)
        DispatchQueue.main.async { prime(in: host) }
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) { }

    private func prime(in container: UIView) {
        let tf = UITextField(frame: .zero)
        tf.isHidden = true

        let bar = UIToolbar(frame: CGRect(
            x: 0, y: 0,
            width: max(1, widthProvider()),
            height: 44
        ))
        bar.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)]
        tf.inputAccessoryView = bar

        container.addSubview(tf)

        tf.becomeFirstResponder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            tf.resignFirstResponder()
            tf.removeFromSuperview()
            onDone()
        }
    }
}

// MARK: - Debug Helpers (PRESERVED)
private func dlog(_ msg: String) {
    NSLog("[SwapTabDBG] \(msg)")
}

private func format(_ size: CGSize) -> String {
    "(\(Int(size.width))x\(Int(size.height)))"
}
