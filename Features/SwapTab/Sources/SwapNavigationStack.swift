import SwiftUI
import Swap
import Primitives
import WalletsService
import SwapService
import Preferences
import Keystore
import PriceAlertService
import Assets
import PrimitivesComponents
import Components
import TransactionsService
import BannerService
import PriceService
import Store // for TransferDataAction
import UIKit  // keyboard notifications

public struct SwapNavigationStack: View {
    // MARK: - Inputs
    let wallet: Wallet
    let walletsService: WalletsService
    let swapQuotesProvider: SwapQuotesProvidable
    let swapQuoteDataProvider: SwapQuoteDataProvidable
    let keystore: any Keystore
    let priceAlertService: PriceAlertService

    // Kept so MainTabView does not need to change its signature again.
    let transactionsService: TransactionsService
    let priceObserverService: PriceObserverService
    let priceService: PriceService
    let bannerService: BannerService

    // Shared instance so both tabs reuse fetched data / cache
    let trendingViewModel: TrendingTokensViewModel

    /// Call this to open the *existing* Asset scene in the Wallet stack.
    let onOpenAsset: (Asset) -> Void
    let onSwap: TransferDataAction

    // MARK: - State
    @State private var viewModel: SwapSceneViewModel  // keep @State – VM uses @Observable

    // Section expanders
    @State private var isTrendingExpanded = true
    @State private var isNewListingsExpanded = true

    // Independent filter sheets
    @State private var showTrendingFilterSheet = false
    @State private var showNewListingsFilterSheet = false

    // Trending filters (independent, but seeded from repo)
    @State private var trendingSortBy: TrendingSortOption = .rank
    @State private var trendingNetwork: TrendingNetwork = .solana

    // New Listings filters (independent, but seeded from repo)
    @State private var newListingsNetwork: TrendingNetwork = .solana
    @State private var newListingsLimit: Int = 10
    @State private var memePlatformEnabled: Bool = false

    // Debug / layout state
    @State private var rootSize: CGSize = .zero
    @State private var didAppearOnce = false
    @State private var didPrimeAccessory = false
    @State private var didNudgeOnce = false     // NEW: track first keyboard show nudge
    @State private var viewCycle: Int = 0       // NEW: forces a tiny re-render of SwapScene

    // Shared repo for global selection + cache
    @ObservedObject private var repo = MarketDataRepository.shared

    // MARK: - Init
    public init(
        wallet: Wallet,
        asset: Asset,
        walletsService: WalletsService,
        swapQuotesProvider: SwapQuotesProvidable,
        swapQuoteDataProvider: SwapQuoteDataProvidable,
        keystore: any Keystore,
        priceAlertService: PriceAlertService,
        transactionsService: TransactionsService,
        priceObserverService: PriceObserverService,
        priceService: PriceService,
        bannerService: BannerService,
        trendingViewModel: TrendingTokensViewModel,
        onOpenAsset: @escaping (Asset) -> Void,
        onSwap: TransferDataAction = nil
    ) {
        self.wallet = wallet
        self.walletsService = walletsService
        self.swapQuotesProvider = swapQuotesProvider
        self.swapQuoteDataProvider = swapQuoteDataProvider
        self.keystore = keystore
        self.priceAlertService = priceAlertService
        self.transactionsService = transactionsService
        self.priceObserverService = priceObserverService
        self.priceService = priceService
        self.bannerService = bannerService
        self.trendingViewModel = trendingViewModel
        self.onOpenAsset = onOpenAsset
        self.onSwap = onSwap

        _viewModel = State(initialValue: SwapSceneViewModel(
            preferences: Preferences.standard,
            wallet: wallet,
            asset: asset, // keep Solana as "You pay"
            walletsService: walletsService,
            swapQuotesProvider: swapQuotesProvider,
            swapQuoteDataProvider: swapQuoteDataProvider,
            onSwap: onSwap
        ))
    }

    // MARK: - Subtitles (computed from the repo so all screens mirror)
    private var trendingSubtitle: String {
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

    private var newListingsSubtitle: String {
        let base = repo.selectedNewListingsChain.capitalized
        let memeSuffix = (repo.selectedNewListingsChain == "solana" && memePlatformEnabled) ? " • memes" : ""
        return base + memeSuffix
    }

    // MARK: - Body
    public var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Swap interface
                    // IMPORTANT: give SwapScene a stable, but cycle-able id so we can reattach toolbar once.
                    SwapScene(model: viewModel)
                        .id(viewCycle)                 // NEW
                        .frame(height: 500)

                    // Trending tokens (uses shared view model)
                    SwapTrendingSection(
                        tokens: trendingViewModel.trendingTokens,
                        isExpanded: $isTrendingExpanded,
                        subtitle: trendingSubtitle,
                        onTokenTap: handleTrendingTokenSelection,
                        onFilterTap: { showTrendingFilterSheet = true },
                        title: "Trending tokens"
                    )

                    // New listings (uses shared view model)
                    SwapNewListingsSection(
                        items: trendingViewModel.newListingTokens,
                        isExpanded: $isNewListingsExpanded,
                        subtitle: newListingsSubtitle,
                        onItemTap: handleNewListingSelection,
                        onFilterTap: { showNewListingsFilterSheet = true },
                        title: "New listings"
                    )
                }
            }

            // Invisible geometry reader (debug only)
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

            // One-time keyboard accessory "primer"
            if !didPrimeAccessory && rootSize.width > 0 {
                KeyboardAccessoryPrimer(
                    widthProvider: { rootSize.width },
                    onDone: { didPrimeAccessory = true; dlog("Primer complete (width=\(Int(rootSize.width)))") }
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
            // Do NOT auto-focus on first land; user tap should bring the correct toolbar.
            viewModel.clearFocus()
            dlog("onAppear → clearFocus() (didAppearOnce=\(didAppearOnce))")
            if onSwap == nil {
                dlog("WARNING: onSwap is nil – confirmation screen will not be shown.")
            }
            if didAppearOnce == false {
                didAppearOnce = true
            }
        }

        .task {
            seedFromRepo()
            await refreshTrendingTokens()
            await refreshNewListingTokens()
        }

        // TRENDING filter sheet
        .sheet(isPresented: $showTrendingFilterSheet) {
            SwapTrendingFilterSheet(
                sortBy: $trendingSortBy,
                selectedNetwork: $trendingNetwork,
                memePlatformEnabled: .constant(false),
                isPresented: $showTrendingFilterSheet,
                onApply: {
                    Task { await refreshTrendingTokens() }
                }
            )
        }

        // NEW LISTINGS filter sheet
        .sheet(isPresented: $showNewListingsFilterSheet) {
            SwapNewListingsFilterSheet(
                selectedNetwork: $newListingsNetwork,
                memePlatformEnabled: $memePlatformEnabled,
                limit: $newListingsLimit,
                isPresented: $showNewListingsFilterSheet,
                onApply: {
                    Task { await refreshNewListingTokens() }
                }
            )
        }

        // VM-driven sheets
        .sheet(item: Binding<SwapSheetType?>(
            get: { viewModel.isPresentedInfoSheet },
            set: { viewModel.isPresentedInfoSheet = $0 }
        )) { (sheetType: SwapSheetType) in
            switch sheetType {
            case .selectAsset(let type):
                NavigationStack {
                    SelectAssetScene(
                        model: SelectAssetViewModel(
                            wallet: wallet,
                            selectType: mapSwapTypeToSelectType(type),
                            assetsService: walletsService.assetsService,
                            walletsService: walletsService,
                            priceAlertService: priceAlertService,
                            selectAssetAction: { asset in
                                viewModel.onFinishAssetSelection(asset: asset)
                            }
                        )
                    )
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Done") { viewModel.isPresentedInfoSheet = nil }
                        }
                    }
                }
            case .swapProvider:
                EmptyView()
            case .info:
                Text("Info").padding()
            }
        }

        // MARK: - Keyboard debug + one-time nudge
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            dlog("keyboardWillShow → \(describeKeyboard(note)) | rootSize=\(format(rootSize))")
            // Nudge exactly once on the first show inside the tab to reattach the toolbar
            if !didNudgeOnce {
                didNudgeOnce = true
                dlog("First keyboardWillShow → issuing one-time reattach nudge")
                viewModel.clearFocus()
                // Tiny cycle so SwiftUI reattaches modifiers after layout is settled
                DispatchQueue.main.async {
                    viewCycle += 1
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { note in
            dlog("keyboardDidShow  → \(describeKeyboard(note)) | rootSize=\(format(rootSize))")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
            dlog("keyboardWillHide → \(describeKeyboard(note))")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { note in
            dlog("keyboardDidHide  → \(describeKeyboard(note))")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            dlog("keyboardWillChangeFrame → \(describeKeyboard(note))")
        }
    }

    // MARK: - Seed local filter state from repo (unchanged)
    private func seedFromRepo() {
        if let net = TrendingNetwork(rawValue: repo.selectedChain) {
            trendingNetwork = net
        }
        switch repo.sortBy {
        case "rank":        trendingSortBy = .rank
        case "liquidity":   trendingSortBy = .liquidity
        default:            trendingSortBy = .volume // "volume24hUSD"
        }

        if let nlNet = TrendingNetwork(rawValue: repo.selectedNewListingsChain) {
            newListingsNetwork = nlNet
        }
    }

    // MARK: - Data refresh (unchanged)
    private func refreshTrendingTokens() async {
        let sortType = (trendingSortBy == .rank) ? "asc" : "desc"

        if repo.selectedChain != trendingNetwork.apiValue { repo.selectedChain = trendingNetwork.apiValue }
        if repo.sortBy != trendingSortBy.apiValue { repo.sortBy = trendingSortBy.apiValue }
        if repo.sortType != sortType { repo.sortType = sortType }

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

    // MARK: - Actions (unchanged)
    private func handleTrendingTokenSelection(_ token: TrendingToken) {
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
                try walletsService.assetsService.addNewAsset(walletId: wallet.walletId, asset: asset)
                await walletsService.enableAssets(walletId: wallet.walletId, assetIds: [asset.id], enabled: true)
            } catch {
                await walletsService.enableAssets(walletId: wallet.walletId, assetIds: [asset.id], enabled: true)
            }

            await MainActor.run {
                viewModel.onFinishAssetSelection(asset: asset)
                onOpenAsset(asset)
            }
        }
    }

    private func handleNewListingSelection(_ item: NewListingToken) {
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
                try walletsService.assetsService.addNewAsset(walletId: wallet.walletId, asset: asset)
                await walletsService.enableAssets(walletId: wallet.walletId, assetIds: [asset.id], enabled: true)
            } catch {
                await walletsService.enableAssets(walletId: wallet.walletId, assetIds: [asset.id], enabled: true)
            }

            await MainActor.run {
                viewModel.onFinishAssetSelection(asset: asset)
                onOpenAsset(asset)
            }
        }
    }

    private func getDecimalsForChain(_ chain: Chain) -> Int32 {
        switch chain {
        case .solana: return 9
        case .ethereum, .arbitrum, .optimism, .polygon, .base, .zkSync: return 18
        case .smartChain: return 18
        case .avalancheC: return 18
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

// MARK: - Debug helpers

private func dlog(_ msg: String) {
    NSLog("[SwapTabDBG] \(msg)")
}

private func format(_ size: CGSize) -> String {
    "(\(Int(size.width))x\(Int(size.height)))"
}

private func describeKeyboard(_ note: Notification) -> String {
    let info = note.userInfo ?? [:]
    let endFrame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
    let isLocal = (info[UIResponder.keyboardIsLocalUserInfoKey] as? NSNumber)?.boolValue ?? false
    let dur = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
    let curveRaw = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.intValue ?? 0
    return "end=\(String(format: "{x:%.1f y:%.1f w:%.1f h:%.1f}", endFrame.origin.x, endFrame.origin.y, endFrame.width, endFrame.height)), isLocal=\(isLocal), duration=\(String(format: "%.3f", dur)), curve=\(curveRaw)"
}

//
// MARK: - One-time keyboard accessory “primer”
//

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

// MARK: - Sections / Rows / Filter sheets (unchanged)

struct SwapTrendingSection: View {
    let tokens: [TrendingToken]
    @Binding var isExpanded: Bool
    let subtitle: String
    let onTokenTap: (TrendingToken) -> Void
    let onFilterTap: () -> Void
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: onFilterTap) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(UIColor.secondarySystemBackground))

            if isExpanded && !tokens.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(tokens.prefix(10).enumerated()), id: \.offset) { index, token in
                        SwapTrendingTokenRow(
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
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct SwapNewListingsSection: View {
    let items: [NewListingToken]
    @Binding var isExpanded: Bool
    let subtitle: String
    let onItemTap: (NewListingToken) -> Void
    let onFilterTap: () -> Void
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: onFilterTap) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(UIColor.secondarySystemBackground))

            if isExpanded && !items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(10).enumerated()), id: \.offset) { index, item in
                        SwapNewListingRow(item: item, rank: index + 1) {
                            onItemTap(item)
                        }
                        if index < min(9, items.count - 1) {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct SwapTrendingTokenRow: View {
    let token: TrendingToken
    let rank: Int
    let onTap: () -> Void

    var priceChangeColor: Color {
        guard let change = token.priceChangePercentage24h else { return .gray }
        return change >= 0 ? .green : .red
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
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 20)

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
                    Text(token.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(token.symbol.uppercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedPrice)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)

                    if let change = token.priceChangePercentage24h {
                        Text("\(change >= 0 ? "+" : "")\(String(format: "%.2f", change))%")
                            .font(.caption)
                            .foregroundColor(priceChangeColor)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SwapNewListingRow: View {
    let item: NewListingToken
    let rank: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                AsyncImage(url: URL(string: item.logoURI ?? "")) { phase in
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
                    Text(item.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(item.symbol.uppercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let liq = item.liquidity {
                    Text("$" + formatNumber(liq))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatNumber(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "%.1fm", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fk", v / 1_000) }
        return String(format: "%.0f", v)
    }
}

struct SwapTrendingFilterSheet: View {
    @Binding var sortBy: TrendingSortOption
    @Binding var selectedNetwork: TrendingNetwork
    @Binding var memePlatformEnabled: Bool // ignored for trending
    @Binding var isPresented: Bool
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Network") {
                    ForEach(TrendingNetwork.allCases) { network in
                        Button(action: { selectedNetwork = network }) {
                            HStack {
                                Text(network.displayText).foregroundColor(.primary)
                                Spacer()
                                if selectedNetwork == network {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Sort by") {
                    ForEach(TrendingSortOption.allCases) { option in
                        Button(action: { sortBy = option }) {
                            HStack {
                                Text(option.displayText).foregroundColor(.primary)
                                Spacer()
                                if sortBy == option {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
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

struct SwapNewListingsFilterSheet: View {
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
                        Button(action: { selectedNetwork = network }) {
                            HStack {
                                Text(network.displayText).foregroundColor(.primary)
                                Spacer()
                                if selectedNetwork == network {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if selectedNetwork == .solana {
                    Section("Options") {
                        Toggle("Include Meme Platforms", isOn: $memePlatformEnabled)
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
