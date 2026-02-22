// Copyright (c). Gem Wallet. All rights reserved.

import SwiftUI

@Observable
final class NavigationStateManager: Sendable {
    @MainActor
    var wallet = NavigationPath()
    @MainActor
    var swap = NavigationPath()          // 👈 add this
    @MainActor
    var collections = NavigationPath()
    @MainActor
    var activity = NavigationPath()
    @MainActor
    var settings = NavigationPath()
    @MainActor
    var markets = NavigationPath()

    @MainActor
    var selectedTab: TabItem = .wallet
    @MainActor
    var previousSelectedTab: TabItem = .wallet

    @MainActor
    var walletTabReselected = false
    @MainActor
    var swapTabReselected = false        // 👈 optional but useful parity

    init() {}
}

// MARK: - Business Logic

@MainActor
extension NavigationStateManager {
    func select(tab: TabItem) {
        selectedTab = tab

        // back to root if selected same tab, if some routes already in stack
        guard tab != previousSelectedTab else {
            backToRoot(tab: tab)
            return
        }

        previousSelectedTab = selectedTab
    }

    func backToRoot(tab: TabItem) {
        // Keep existing behaviour for wallet (and add swap parity)
        if tab == .wallet, wallet.isEmpty {
            walletTabReselected.toggle()
        }
        if tab == .swap, swap.isEmpty {
            swapTabReselected.toggle()
        }

        switch tab {
        case .wallet: resetPath(&wallet)
        case .swap: resetPath(&swap)                 // 👈 add this
        case .collections: resetPath(&collections)
        case .activity: resetPath(&activity)
        case .settings: resetPath(&settings)
        case .markets: resetPath(&markets)
        }
    }

    private func resetPath(_ path: inout NavigationPath) {
        guard !path.isEmpty else { return }
        path.removeLast(path.count)
    }

    func clearAll() {
        for tabItem in TabItem.allCases {
            backToRoot(tab: tabItem)
        }
    }
}
