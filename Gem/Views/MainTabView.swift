// Copyright (c). Gem Wallet. All rights reserved.

import SwiftUI
import Primitives
import PrimitivesComponents
import GRDB
import GRDBQuery
import Store
import Localization
import Style
import NFT
import TransactionsService
import WalletTab
import Transactions
import Assets
import PriceAlerts
import Components

// Swap + confirm
import Swap
import SwapService
import Transfer

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.walletsService) private var walletsService
    @Environment(\.bannerService) private var bannerService
    @Environment(\.navigationState) private var navigationState
    @Environment(\.navigationPresenter) private var presenter
    @Environment(\.nftService) private var nftService
    @Environment(\.priceService) private var priceService
    @Environment(\.priceObserverService) private var priceObserverService
    @Environment(\.observablePreferences) private var observablePreferences
    @Environment(\.walletService) private var walletService
    @Environment(\.assetsService) private var assetsService
    @Environment(\.perpetualObserverService) private var perpetualObserverService
    @Environment(\.priceAlertService) private var priceAlertService
    @Environment(\.transactionsService) private var transactionsService

    // Swap deps
    @Environment(\.keystore) private var keystore
    @Environment(\.swapService) private var swapService

    private let model: MainTabViewModel

    @Query<TransactionsCountRequest>
    private var transactions: Int

    @State private var isPresentingToastMessage: ToastMessage?

    // Swap confirm
    @State private var pendingTransferData: TransferData?

    private var tabViewSelection: Binding<TabItem> {
        Binding(
            get: { navigationState.selectedTab },
            set: { onSelect(tab: $0) }
        )
    }

    init(model: MainTabViewModel) {
        self.model = model
        _transactions = Query(constant: model.transactionsCountRequest)
    }

    var body: some View {
        TabView(selection: tabViewSelection) {
            WalletNavigationStack(
                model: WalletSceneViewModel(
                    walletsService: walletsService,
                    bannerService: bannerService,
                    walletService: walletService,
                    observablePreferences: observablePreferences,
                    wallet: model.wallet,
                    isPresentingSelectedAssetInput: presenter.isPresentingAssetInput
                )
            )
            .tabItem {
                tabItem(Localized.Wallet.title, Images.Tabs.wallet)
            }
            .tag(TabItem.wallet)

            if model.isMarketEnabled {
                MarketsNavigationStack()
                    .tabItem {
                        tabItem("Markets", Images.Tabs.markets)
                    }
                    .tag(TabItem.markets)
            }

            if model.isCollectionsEnabled {
                CollectionsNavigationStack(
                    model: CollectionsViewModel(
                        nftService: nftService,
                        walletService: walletService,
                        wallet: model.wallet
                    ),
                    isPresentingSelectedAssetInput: presenter.isPresentingAssetInput
                )
                .tabItem {
                    tabItem(Localized.Nft.collections, Images.Tabs.collections)
                }
                .tag(TabItem.collections)
            }

            // ✅ Swap tab (re-added)
            SwapNavigationStack(
                wallet: model.wallet,
                defaultAsset: getDefaultSwapAsset(),
                swapQuotesProvider: SwapQuotesProvider(swapService: swapService),
                swapQuoteDataProvider: SwapQuoteDataProvider(keystore: keystore, swapService: swapService),
                priceAlertService: priceAlertService,
                onOpenAsset: { asset in
                    navigationState.selectedTab = .wallet
                    navigationState.wallet.append(Scenes.Asset(asset: asset))
                },
                onSwapBuilt: { data in
                    pendingTransferData = data
                }
            )
            .tabItem {
                tabItem("Swap", Image(systemName: "arrow.left.arrow.right.circle"))
            }
            .tag(TabItem.swap)

            TransactionsNavigationStack(
                model: TransactionsViewModel(
                    transactionsService: transactionsService,
                    walletService: walletService,
                    wallet: model.wallet,
                    type: .all
                )
            )
            .tabItem {
                tabItem(Localized.Activity.title, Images.Tabs.activity)
            }
            .badge(transactions)
            .tag(TabItem.activity)

            SettingsNavigationStack(
                walletId: model.wallet.walletId,
                priceService: priceService,
                isPresentingSupport: presenter.isPresentingSupport
            )
            .tabItem {
                tabItem(Localized.Settings.title, Images.Tabs.settings)
            }
            .tag(TabItem.settings)
        }

        // ✅ Selected asset flow (new repo way)
        .sheet(item: presenter.isPresentingAssetInput) { input in
            SelectedAssetNavigationStack(
                input: input,
                wallet: model.wallet,
                onComplete: { onComplete(type: input.type) }
            )
        }

        // ✅ Set price alert (new repo way)
        .sheet(item: presenter.isPresentingPriceAlert) { input in
            SetPriceAlertNavigationStack(
                model: SetPriceAlertViewModel(
                    walletId: model.wallet.walletId,
                    assetId: input.assetId,
                    priceAlertService: priceAlertService,
                    price: input.price,
                    onComplete: onSetPriceAlertComplete
                )
            )
        }

        // ✅ Confirm transfer after swap build
        .sheet(
            isPresented: Binding(
                get: { pendingTransferData != nil },
                set: { if !$0 { pendingTransferData = nil } }
            )
        ) {
            if let data = pendingTransferData {
                ConfirmTransferNavigationStack(
                    wallet: model.wallet,
                    transferData: data,
                    onComplete: { pendingTransferData = nil }
                )
            }
        }

        .toast(message: $isPresentingToastMessage)
        .onChange(of: model.walletId, onWalletIdChange)
        .onChange(of: navigationState.selectedTab) { oldTab, newTab in
            trackTabChange(from: oldTab, to: newTab)
        }
        .taskOnce {
            Task { await connectObservers() }
        }
        .onChange(of: scenePhase) { (_, newPhase) in
            switch newPhase {
            case .active:
                Task { await connectObservers() }
                debugLog("App moved to active — restart websocket, refresh UI…")
            case .inactive:
                Task { await disconnectObservers() }
                debugLog("App is inactive — e.g. transitioning or showing interruption UI")
            case .background:
                debugLog("App went to background — tear down connections, save state…")
            @unknown default:
                break
            }
        }
    }
}

// MARK: - UI Components

extension MainTabView {
    @ViewBuilder
    private func tabItem(_ title: String, _ image: Image) -> Label<Text, Image> {
        Label(
            title: { Text(title) },
            icon: { image }
        )
    }
}

// MARK: - Actions

extension MainTabView {
    private func onSelect(tab: TabItem) {
        navigationState.select(tab: tab)
    }
    
    // Track tab changes
    private func trackTabChange(from oldTab: TabItem, to newTab: TabItem) {
        let pageName: String
        
        switch newTab {
        case .wallet:
            pageName = "wallet"
            AnalyticsService.shared.trackPortfolioViewed()
        case .markets:
            pageName = "markets"
        case .collections:
            pageName = "collections"
        case .swap:
            pageName = "swap"
        case .activity:
            pageName = "activity"
            AnalyticsService.shared.trackTransactionHistoryViewed()
        case .settings:
            pageName = "settings"
        @unknown default:
            pageName = "unknown"
        }
        
        AnalyticsService.shared.trackPageView(pageName: pageName)
    }

    private func onWalletIdChange() {
        navigationState.clearAll()
        navigationState.selectedTab = .wallet

        Task {
            try await priceObserverService.setupAssets()
            await perpetualObserverService.connect(for: model.wallet)
        }
    }

    private func connectObservers() async {
        await priceObserverService.connect()
        await perpetualObserverService.connect(for: model.wallet)
    }

    private func disconnectObservers() async {
        await priceObserverService.disconnect()
        await perpetualObserverService.disconnect()
    }

    private func onSetPriceAlertComplete(message: String) {
        presenter.isPresentingPriceAlert.wrappedValue = nil
        isPresentingToastMessage = .priceAlert(message: message)
    }

    private func onComplete(type: SelectedAssetType) {
        switch type {
        case .receive, .stake, .buy, .sell:
            presenter.isPresentingAssetInput.wrappedValue = nil

        case let .send(type):
            switch type {
            case .nft:
                if navigationState.selectedTab == .collections {
                    navigationState.collections.removeAll()
                    navigationState.activity.removeAll()
                    navigationState.selectedTab = .activity
                }
            case .asset:
                break
            }
            presenter.isPresentingAssetInput.wrappedValue = nil

        case let .swap(fromAsset, _):
            Task {
                let asset = try await assetsService.getOrFetchAsset(for: fromAsset.id)

                switch navigationState.selectedTab {
                case .wallet:
                    navigationState.wallet = NavigationPath([Scenes.Asset(asset: asset)])
                case .activity:
                    navigationState.wallet = NavigationPath([Scenes.Asset(asset: asset)])
                    navigationState.selectedTab = .wallet
                case .markets, .settings, .collections, .swap:
                    break
                @unknown default:
                    break
                }

                presenter.isPresentingAssetInput.wrappedValue = nil
            }
        }
    }

    private func getDefaultSwapAsset() -> Asset {
        if let solanaAccount = model.wallet.accounts.first(where: { $0.chain == .solana }) {
            return solanaAccount.chain.asset
        }
        if let firstAccount = model.wallet.accounts.first {
            return firstAccount.chain.asset
        }
        return Chain.solana.asset
    }
}
