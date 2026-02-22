// Copyright (c). Gem Wallet. All rights reserved.

import Foundation
import BigInt
import Blockchain
import Components
import Localization
import Primitives
import PrimitivesComponents
import WalletConnector
import InfoSheet
import Validators
import SwiftUI
import Swap

@Observable
@MainActor
public final class ConfirmTransferSceneViewModel {
    var feeModel: NetworkFeeSceneViewModel
    var state: StateViewType<TransactionInputViewModel> = .loading {
        didSet {
            onStateChange(state: state)
        }
    }

    var confirmingState: StateViewType<Bool> = .noData {
        didSet {
            if case .error(let error) = confirmingState {
                isPresentingAlertMessage = AlertMessage(
                    title: Localized.Errors.transferError,
                    message: error.localizedDescription
                )
            } else {
                isPresentingAlertMessage = nil
            }
        }
    }

    var isPresentingSheet: ConfirmTransferSheetType?
    var isPresentingAlertMessage: AlertMessage?

    private let confirmService: ConfirmService

    private let wallet: Wallet
    private let onComplete: VoidAction
    private let confirmTransferDelegate: TransferDataCallback.ConfirmTransferDelegate?

    private var data: TransferData
    private var metadata: TransferDataMetadata?

    public init(
        wallet: Wallet,
        data: TransferData,
        confirmService: ConfirmService,
        confirmTransferDelegate: TransferDataCallback.ConfirmTransferDelegate? = .none,
        onComplete: VoidAction
    ) {
        self.wallet = wallet
        self.data = data
        self.confirmService = confirmService
        self.confirmTransferDelegate = confirmTransferDelegate
        self.onComplete = onComplete

        self.feeModel = NetworkFeeSceneViewModel(
            chain: data.chain,
            priority: confirmService.defaultPriority(for: data.type)
        )

        self.metadata = try? confirmService.getMetadata(wallet: wallet, data: data)
    }

    var title: String { dataModel.title }

    var websiteURL: URL? { dataModel.websiteURL }
    var websiteTitle: String { Localized.Settings.website }

    var senderAddress: String { (try? wallet.account(for: dataModel.chain).address) ?? "" }
    var senderAddressExplorerUrl: URL { senderLink.url }
    var senderExplorerText: String { Localized.Transaction.viewOn(senderLink.name) }

    var progressMessage: String { Localized.Common.loading }

    var confirmButtonModel: ConfirmButtonViewModel {
        ConfirmButtonViewModel(
            state: state,
            icon: confirmButtonIcon,
            onAction: { [weak self] in
                guard let self else { return }
                if case .data(let data) = state, data.isReady {
                    onSelectConfirmTransfer()
                } else {
                    self.fetch()
                }
            }
        )
    }

    var detailsViewModel: ConfirmDetailsViewModel {
        ConfirmDetailsViewModel(type: data.type, metadata: metadata)
    }
}

// MARK: - ListSectionProvideable

extension ConfirmTransferSceneViewModel: ListSectionProvideable {
    public var sections: [ListSection<ConfirmTransferItem>] {
        [
            ListSection(type: .header, [.header]),
            ListSection(type: .details, [.app, .network, .sender, .recipient, .memo, .details]),
            ListSection(type: .fee, [.networkFee]),
            ListSection(type: .error, [.error])
        ]
    }

    public func itemModel(for item: ConfirmTransferItem) -> any ItemModelProvidable<ConfirmTransferItemModel> {
        switch item {
        case .header:
            ConfirmHeaderViewModel(inputModel: state.value, metadata: metadata, data: data)
        case .app:
            ConfirmAppViewModel(type: data.type)
        case .sender:
            ConfirmSenderViewModel(wallet: wallet)
        case .network:
            ConfirmNetworkViewModel(type: data.type)
        case .recipient:
            ConfirmRecipientViewModel(
                model: dataModel,
                addressName: try? confirmService.getAddressName(chain: dataModel.chain, address: dataModel.recipient.address),
                addressLink: confirmService.getExplorerLink(chain: dataModel.chain, address: dataModel.recipient.address)
            )
        case .memo:
            ConfirmMemoViewModel(type: data.type, recipientData: data.recipientData)
        case .details:
            detailsViewModel
        case .networkFee:
            ConfirmNetworkFeeViewModel(
                state: state,
                title: feeModel.title,
                value: feeModel.value,
                fiatValue: feeModel.fiatValue,
                infoAction: onSelectNetworkFeeInfo
            )
        case .error:
            ConfirmErrorViewModel(
                state: state,
                onSelectListError: onSelectListError
            )
        }
    }
}

// MARK: - Business Logic

extension ConfirmTransferSceneViewModel {
    func onSelectListError(error: Error) {
        switch error {
        case let error as TransferAmountCalculatorError:
            switch error {
            case let .insufficientBalance(asset):
                isPresentingSheet = .info(.insufficientBalance(asset, image: AssetViewModel(asset: asset).assetImage))
            case let .insufficientNetworkFee(asset, required):
                isPresentingSheet = .info(.insufficientNetworkFee(asset, image: AssetViewModel(asset: asset).assetImage, required: required, action: onSelectBuy))
            case let .minimumAccountBalanceTooLow(asset, required):
                isPresentingSheet = .info(.accountMinimalBalance(asset, required: required))
            }
        case let error as ScanTransactionError:
            switch error {
            case .malicious:
                isPresentingSheet = .info(.maliciousTransaction)
            case let .memoRequired(symbol):
                isPresentingSheet = .info(.memoRequired(symbol: symbol))
            }
        default:
            if let chainError = ChainCoreError.fromError(error) {
                switch chainError {
                case .dustThreshold:
                    let asset = dataModel.asset
                    isPresentingSheet = .info(.dustThreshold(asset.chain, image: AssetViewModel(asset: asset).assetImage))
                case .feeRateMissed, .cantEstimateFee, .incorrectAmount:
                    break
                }
            }
        }
    }

    func onSelectNetworkFeeInfo() {
        isPresentingSheet = .info(.networkFee(dataModel.chain))
    }

    func onSelectOpenWebsiteURL() {
        if let websiteURL {
            isPresentingSheet = .url(websiteURL)
        }
    }

    func onSelectOpenSenderAddressURL() {
        isPresentingSheet = .url(senderAddressExplorerUrl)
    }

    func onSelectFeePicker() {
        isPresentingSheet = .networkFeeSelector
    }

    func onSelectSwapDetails() {
        isPresentingSheet = .swapDetails
    }

    func onSelectPerpetualDetails(_ model: PerpetualDetailsViewModel) {
        isPresentingSheet = .perpetualDetails(model)
    }

    func onChangeFeePriority(_ priority: FeePriority) async {
        await fetch()
    }

    func fetch() {
        Task {
            await fetch()
        }
    }
}

// MARK: - Private

extension ConfirmTransferSceneViewModel {
    private func onStateChange(state: StateViewType<TransactionInputViewModel>) {
        switch state {
        case .data(let data):
            if case .failure(let error) = data.transferAmount {
                onSelectListError(error: error)
            }
        case .error(let error as TransferAmountCalculatorError):
            onSelectListError(error: error)
        case .error(let error as ScanTransactionError):
            onSelectListError(error: error)
        case .error, .loading, .noData:
            break
        }
    }

    private func onSelectBuy() {
        isPresentingSheet = .fiatConnect(
            assetAddress: feeAssetAddress,
            walletId: wallet.walletId
        )
    }
    
    private func onSelectConfirmTransfer() {
        guard let value = state.value,
              let transactionData = value.transactionData,
              case .success(let amount) = value.transferAmount
        else { return }
        
        // 📊 Track trade initiated
        trackTransferInitiated()
        
        confirmTransfer(transactionData: transactionData, amount: amount)
    }

    private func confirmTransfer(
        transactionData: TransactionData,
        amount: TransferAmount
    ) {
        Task {
            await processConfirmation(
                transactionData: transactionData,
                amount: amount
            )
            if case .data(_) = confirmingState {
                onComplete?()
            }
        }
    }


    private func fetch() async {
        state = .loading
        feeModel.reset()

        do {
            let metadata = try confirmService.getMetadata(wallet: wallet, data: data)
            try TransferAmountCalculator().validateNetworkFee(metadata.feeAvailable, feeAssetId: metadata.feeAssetId)

            let transferTransactionData = try await confirmService.loadTransferTransactionData(
                wallet: wallet, data: data,
                priority: feeModel.priority,
                available: metadata.available
            )
            let transferAmount = calculateTransferAmount(
                assetBalance: metadata.assetBalance,
                assetFeeBalance: metadata.assetFeeBalance,
                fee: transferTransactionData.transactionData.fee.fee
            )

            self.metadata = metadata
            self.feeModel.update(rates: transferTransactionData.rates)
            self.updateState(
                with: transactionInputViewModel(
                    transferAmount: transferAmount,
                    input: transferTransactionData.transactionData,
                    metaData: metadata
                )
            )
        } catch {
            if !error.isCancelled {
                state = .error(error)
                debugLog("preload transaction error: \(error)")
            }
        }
    }

    private func processConfirmation(transactionData: TransactionData, amount: TransferAmount) async {
        confirmingState = .loading
        do {
            let input = TransferConfirmationInput(
                data: state.value!.data,
                wallet: wallet,
                transactionData: transactionData,
                amount: amount,
                delegate: confirmTransferDelegate
            )
            try await confirmService.executeTransfer(input: input)
            if let data = input.data.type.recentActivityData {
                confirmService.updateRecent(data: data, walletId: wallet.walletId)
            }
            confirmingState = .data(true)
            
            // 📊 Track successful transaction
            trackTransferCompleted(transactionData: transactionData, amount: amount)
            
        } catch {
            confirmingState = .error(error)
            
            // 📊 Track failed transaction
            trackTransferFailed(error: error)
            
            debugLog("confirm transaction error: \(error)")
        }
    }

    private func updateState(with model: TransactionInputViewModel) {
        feeModel.update(
            value: model.networkFeeText,
            fiatValue: model.networkFeeFiatText
        )
        state = .data(model)
    }

    private func calculateTransferAmount(
        assetBalance: Balance,
        assetFeeBalance: Balance,
        fee: BigInt
    ) -> TransferAmountValidation {
        TransferAmountCalculator().validate(input: TransferAmountInput(
            asset: dataModel.asset,
            assetBalance: assetBalance,
            value: dataModel.data.value,
            availableValue: availableValue,
            assetFee: dataModel.asset.feeAsset,
            assetFeeBalance: assetFeeBalance,
            fee: fee,
            transferData: data
        ))
    }

    private func transactionInputViewModel(
        transferAmount: TransferAmountValidation,
        input: TransactionData? = nil,
        metaData: TransferDataMetadata? = nil
    ) -> TransactionInputViewModel {
        TransactionInputViewModel(
            data: data,
            transactionData: input,
            metaData: metaData,
            transferAmount: transferAmount
        )
    }

    private var dataModel: TransferDataViewModel { TransferDataViewModel(data: data) }
    private var availableValue: BigInt { dataModel.availableValue(metadata: metadata) }
    private var senderLink: BlockExplorerLink { confirmService.getExplorerLink(chain: dataModel.chain, address: senderAddress) }
    private var feeAssetAddress: AssetAddress { AssetAddress(asset: dataModel.asset.feeAsset, address: senderAddress)}
    private var confirmButtonIcon: Image? {
        guard !state.isError, state.value?.transferAmount?.isSuccess ?? false,
              let auth = try? confirmService.getPasswordAuthentication(),
              let systemName = KeystoreAuthenticationViewModel(authentication: auth).authenticationImage
        else { return nil }
        return Image(systemName: systemName)
    }
}

// MARK: - Analytics Tracking

extension ConfirmTransferSceneViewModel {
    
    /// Track when transaction/swap is initiated
    private func trackTransferInitiated() {
        let asset = dataModel.asset
        let chain = dataModel.chain
        
        // Check if this is a swap
        if case .swap(let fromAsset, let toAsset, _) = data.type {
            // This is a swap/trade
            AnalyticsService.shared.trackTradeInitiated(
                fromToken: fromAsset.symbol,
                toToken: toAsset.symbol,
                fromAmount: dataModel.data.value.description,
                network: chain.rawValue
            )
        } else {
            // Regular send transaction
            AnalyticsService.shared.trackTransactionSent(
                token: asset.symbol,
                amount: dataModel.data.value.description,
                network: chain.rawValue,
                usdValue: nil
            )
        }
    }
    
    /// Track successful transaction/swap completion
    private func trackTransferCompleted(transactionData: TransactionData, amount: TransferAmount) {
        let chain = dataModel.chain
        
        // Check if this is a swap
        if case .swap(let fromAsset, let toAsset, let swapData) = data.type {
            // This is a swap/trade - track as trade_completed
            
            // Convert raw values to human-readable amounts
            let fromAmount = convertToHumanReadable(
                value: swapData.quote.fromValue,
                decimals: fromAsset.decimals
            )
            let toAmount = convertToHumanReadable(
                value: swapData.quote.toValue,
                decimals: toAsset.decimals
            )
            
            // Calculate USD value (set to 0 if price not available)
            let usdValue = calculateSwapUSDValue(fromAsset: fromAsset, fromAmount: swapData.quote.fromValue)
            
            AnalyticsService.shared.trackTradeCompleted(
                fromToken: fromAsset.symbol,
                toToken: toAsset.symbol,
                fromAmount: fromAmount,
                toAmount: toAmount,
                usdValue: usdValue,
                network: chain.rawValue,
                transactionHash: "pending",
                gasFeeUSD: nil,
                dexProtocol: swapData.quote.providerData.name
            )
        } else {
            // Regular send transaction
            let asset = dataModel.asset
            
            AnalyticsService.shared.trackTransactionSent(
                token: asset.symbol,
                amount: dataModel.data.value.description,
                network: chain.rawValue,
                usdValue: nil
            )
        }
    }
    
    /// Track failed transaction/swap
    private func trackTransferFailed(error: Error) {
        let failureReason = getFailureReason(from: error)
        
        // Check if this is a swap
        if case .swap(let fromAsset, let toAsset, _) = data.type {
            // Track as trade failure
            AnalyticsService.shared.trackTradeFailed(
                fromToken: fromAsset.symbol,
                toToken: toAsset.symbol,
                reason: failureReason,
                errorMessage: error.localizedDescription
            )
        } else {
            // Track as general error
            AnalyticsService.shared.trackError(
                errorType: "transaction_failed",
                errorMessage: error.localizedDescription,
                context: "transfer"
            )
        }
    }
    
    /// Extract failure reason from error
    private func getFailureReason(from error: Error) -> String {
        if let calcError = error as? TransferAmountCalculatorError {
            switch calcError {
            case .insufficientBalance: return "insufficient_balance"
            case .insufficientNetworkFee: return "insufficient_network_fee"
            case .minimumAccountBalanceTooLow: return "minimum_balance_too_low"
            }
        }
        
        if let scanError = error as? ScanTransactionError {
            switch scanError {
            case .malicious: return "malicious_transaction"
            case .memoRequired: return "memo_required"
            }
        }
        
        if let chainError = ChainCoreError.fromError(error) {
            switch chainError {
            case .dustThreshold: return "dust_threshold"
            case .feeRateMissed: return "fee_rate_missed"
            case .cantEstimateFee: return "cant_estimate_fee"
            case .incorrectAmount: return "incorrect_amount"
            }
        }
        
        return "unknown_error"
    }
    
    /// Calculate USD value for swap
    /// Note: Returns 0 if price data not available - can be enhanced later with price service
    private func calculateSwapUSDValue(fromAsset: Asset, fromAmount: String) -> Double {
        // fromAmount is already a string representation of the value
        // For now, return 0 since we don't have price data available
        // TODO: Integrate with price service to get actual USD values
        return 0.0
    }
    
    /// Convert raw blockchain value to human-readable decimal amount
    private func convertToHumanReadable(value: String, decimals: Int32) -> String {
        guard let bigIntValue = BigInt(value) else { return value }
        
        let decimalValue = Decimal(string: bigIntValue.description) ?? 0
        let divisor = pow(Decimal(10), Int(decimals))
        let humanReadable = decimalValue / divisor
        
        return "\(humanReadable)"
    }
}
