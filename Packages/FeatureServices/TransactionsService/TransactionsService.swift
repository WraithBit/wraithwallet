// Copyright (c). Gem Wallet. All rights reserved.

import Foundation
import GemAPI
import Primitives
import Store
import Preferences
import AssetsService
import DeviceService

public final class TransactionsService: Sendable {
    let provider: any GemAPITransactionService
    public let transactionStore: TransactionStore
    let assetsService: AssetsService
    let walletStore: WalletStore
    private let deviceService: any DeviceServiceable
    private let addressStore: AddressStore
    
    public init(
        provider: any GemAPITransactionService = GemAPIService(),
        transactionStore: TransactionStore,
        assetsService: AssetsService,
        walletStore: WalletStore,
        deviceService: any DeviceServiceable,
        addressStore: AddressStore
    ) {
        self.provider = provider
        self.transactionStore = transactionStore
        self.assetsService = assetsService
        self.walletStore = walletStore
        self.deviceService = deviceService
        self.addressStore = addressStore
    }

    public func updateAll(walletId: WalletId) async throws {
        guard let wallet = try walletStore.getWallet(id: walletId) else {
            throw AnyError("Can't get a wallet, walletId: \(walletId.id)")
        }
        let store = WalletPreferences(walletId: walletId)

        let deviceId = try await deviceService.getSubscriptionsDeviceId()
        let response = try await provider.getTransactionsAll(
            deviceId: deviceId,
            walletIndex: wallet.index.asInt,
            fromTimestamp: store.transactionsTimestamp
        )

        if response.transactions.isEmpty {
            return
        }

        try await prefetchAssets(walletId: walletId, transactions: response.transactions)
        try transactionStore.addTransactions(walletId: walletId, transactions: response.transactions)
        try addressStore.addAddressNames(response.addressNames)

        // Use the latest transaction's server-side createdAt instead of wall clock
        // This prevents the timestamp from advancing past unfetched transactions
        let maxCreatedAt = response.transactions
            .map { Int($0.createdAt.timeIntervalSince1970) }
            .max()

        if let maxCreatedAt {
            store.transactionsTimestamp = maxCreatedAt
        }
    }

    public func updateForAsset(wallet: Wallet, assetId: AssetId) async throws {
        let store = WalletPreferences(walletId: wallet.walletId)
        let deviceId = try await deviceService.getSubscriptionsDeviceId()
        let response = try await provider.getTransactionsForAsset(
            deviceId: deviceId,
            walletIndex: wallet.index.asInt,
            asset: assetId,
            fromTimestamp: store.transactionsForAssetTimestamp(assetId: assetId.identifier)
        )
        if response.transactions.isEmpty {
            return
        }

        try await prefetchAssets(walletId: wallet.walletId, transactions: response.transactions)
        try transactionStore.addTransactions(walletId: wallet.walletId, transactions: response.transactions)
        try addressStore.addAddressNames(response.addressNames)

        // Use the latest transaction's server-side createdAt instead of wall clock
        let maxCreatedAt = response.transactions
            .map { Int($0.createdAt.timeIntervalSince1970) }
            .max()

        if let maxCreatedAt {
            store.setTransactionsForAssetTimestamp(assetId: assetId.identifier, value: maxCreatedAt)
        }
    }

    public func addTransaction(walletId: WalletId, transaction: Transaction) throws {
        try transactionStore.addTransactions(walletId: walletId, transactions: [transaction])
    }

    public func getTransaction(walletId: WalletId, transactionId: String) throws -> TransactionExtended {
        try transactionStore.getTransaction(walletId: walletId, transactionId: transactionId)
    }

    private func prefetchAssets(walletId: WalletId, transactions: [Transaction]) async throws {
        let assetIds = transactions.map { $0.assetIds }.flatMap { $0 }
        if assetIds.isEmpty {
            return
        }
        let newAssets = try await assetsService.prefetchAssets(assetIds: assetIds)
        try assetsService.addBalancesIfMissing(walletId: walletId, assetIds: newAssets)
    }
}
