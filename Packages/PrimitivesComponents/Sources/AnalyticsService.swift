// Copyright (c). Gem Wallet. All rights reserved.

import Foundation
import FirebaseAnalytics
import Primitives

/// Service responsible for tracking analytics events throughout the app
public final class AnalyticsService: @unchecked Sendable {
    
    // MARK: - Singleton
    public static let shared = AnalyticsService()
    
    private init() {}
    
    // MARK: - User Events
    
    /// Track when a user connects their wallet
    public func trackWalletConnected(walletType: String, chainId: String? = nil) {
        var parameters: [String: Any] = [
            "wallet_type": walletType,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let chainId = chainId {
            parameters["chain_id"] = chainId
        }
        
        Analytics.logEvent("wallet_connected", parameters: parameters)
        
        #if DEBUG
        print("📊 Analytics: wallet_connected - \(walletType)")
        #endif
    }
    
    /// Track user session start
    public func trackSessionStart() {
        Analytics.logEvent("session_start", parameters: [
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        
        #if DEBUG
        print("📊 Analytics: session_start")
        #endif
    }
    
    /// Track when user disconnects wallet
    public func trackWalletDisconnected() {
        Analytics.logEvent("wallet_disconnected", parameters: [
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        
        #if DEBUG
        print("📊 Analytics: wallet_disconnected")
        #endif
    }
    
    /// Set user properties (call once per user)
    public func setUserProperties(userId: String, walletAddress: String) {
        Analytics.setUserID(userId)
        Analytics.setUserProperty(walletAddress, forName: "wallet_address")
        
        #if DEBUG
        print("📊 Analytics: User properties set for \(userId)")
        #endif
    }
    
    // MARK: - Trading Events
    
    /// Track when a trade is initiated
    public func trackTradeInitiated(
        fromToken: String,
        toToken: String,
        fromAmount: String,
        network: String
    ) {
        let tradingPair = "\(fromToken)/\(toToken)"
        
        Analytics.logEvent("trade_initiated", parameters: [
            "from_token": fromToken,
            "to_token": toToken,
            "trading_pair": tradingPair,
            "from_amount": fromAmount,
            "network": network,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        
        #if DEBUG
        print("📊 Analytics: trade_initiated - \(tradingPair) on \(network)")
        #endif
    }
    
    /// Track when a trade completes successfully
    public func trackTradeCompleted(
        fromToken: String,
        toToken: String,
        fromAmount: String,
        toAmount: String,
        usdValue: Double,
        network: String,
        transactionHash: String,
        gasFeeUSD: Double? = nil,
        dexProtocol: String? = nil
    ) {
        let tradingPair = "\(fromToken)/\(toToken)"
        
        var parameters: [String: Any] = [
            "from_token": fromToken,
            "to_token": toToken,
            "trading_pair": tradingPair,
            "from_amount": fromAmount,
            "to_amount": toAmount,
            "usd_value": usdValue,
            "network": network,
            "transaction_hash": transactionHash,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let gasFeeUSD = gasFeeUSD {
            parameters["gas_fee_usd"] = gasFeeUSD
        }
        
        if let dexProtocol = dexProtocol {
            parameters["dex_protocol"] = dexProtocol
        }
        
        Analytics.logEvent("trade_completed", parameters: parameters)
        
        // Also log as a purchase event for conversion tracking
        Analytics.logEvent(AnalyticsEventPurchase, parameters: [
            AnalyticsParameterCurrency: "USD",
            AnalyticsParameterValue: usdValue,
            AnalyticsParameterItems: [
                [
                    AnalyticsParameterItemID: tradingPair,
                    AnalyticsParameterItemName: "\(fromToken) to \(toToken)",
                    AnalyticsParameterQuantity: 1
                ]
            ]
        ])
        
        #if DEBUG
        print("📊 Analytics: trade_completed - \(tradingPair) $\(usdValue) on \(network)")
        #endif
    }
    
    /// Track when a trade fails
    public func trackTradeFailed(
        fromToken: String,
        toToken: String,
        reason: String,
        errorMessage: String? = nil
    ) {
        let tradingPair = "\(fromToken)/\(toToken)"
        
        var parameters: [String: Any] = [
            "from_token": fromToken,
            "to_token": toToken,
            "trading_pair": tradingPair,
            "failure_reason": reason,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let errorMessage = errorMessage {
            parameters["error_message"] = errorMessage
        }
        
        Analytics.logEvent("trade_failed", parameters: parameters)
        
        #if DEBUG
        print("📊 Analytics: trade_failed - \(tradingPair) - \(reason)")
        #endif
    }
    
    /// Track when user cancels a trade
    public func trackTradeCancelled(
        fromToken: String,
        toToken: String
    ) {
        Analytics.logEvent("trade_cancelled", parameters: [
            "from_token": fromToken,
            "to_token": toToken,
            "trading_pair": "\(fromToken)/\(toToken)",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        
        #if DEBUG
        print("📊 Analytics: trade_cancelled - \(fromToken)/\(toToken)")
        #endif
    }
    
    /// Track first trade milestone
    public func trackFirstTrade(
        fromToken: String,
        toToken: String,
        usdValue: Double
    ) {
        Analytics.logEvent("first_trade", parameters: [
            "from_token": fromToken,
            "to_token": toToken,
            "trading_pair": "\(fromToken)/\(toToken)",
            "usd_value": usdValue,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        
        #if DEBUG
        print("📊 Analytics: first_trade milestone - \(fromToken)/\(toToken)")
        #endif
    }
    
    // MARK: - Transaction Events
    
    /// Track token send transaction
    public func trackTransactionSent(
        token: String,
        amount: String,
        network: String,
        usdValue: Double? = nil
    ) {
        var parameters: [String: Any] = [
            "token": token,
            "amount": amount,
            "network": network,
            "transaction_type": "send",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let usdValue = usdValue {
            parameters["usd_value"] = usdValue
        }
        
        Analytics.logEvent("transaction_sent", parameters: parameters)
        
        #if DEBUG
        print("📊 Analytics: transaction_sent - \(amount) \(token)")
        #endif
    }
    
    /// Track token receive transaction
    public func trackTransactionReceived(
        token: String,
        amount: String,
        network: String,
        usdValue: Double? = nil
    ) {
        var parameters: [String: Any] = [
            "token": token,
            "amount": amount,
            "network": network,
            "transaction_type": "receive",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let usdValue = usdValue {
            parameters["usd_value"] = usdValue
        }
        
        Analytics.logEvent("transaction_received", parameters: parameters)
        
        #if DEBUG
        print("📊 Analytics: transaction_received - \(amount) \(token)")
        #endif
    }
    
    // MARK: - Feature Usage Events
    
    /// Track page/screen views
    public func trackPageView(pageName: String, parameters: [String: Any] = [:]) {
        var allParameters = parameters
        allParameters["page_name"] = pageName
        allParameters["timestamp"] = ISO8601DateFormatter().string(from: Date())
        
        Analytics.logEvent("page_view", parameters: allParameters)
        
        #if DEBUG
        print("📊 Analytics: page_view - \(pageName)")
        #endif
    }
    
    /// Track when user views their portfolio
    public func trackPortfolioViewed() {
        Analytics.logEvent("portfolio_viewed", parameters: [
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        
        #if DEBUG
        print("📊 Analytics: portfolio_viewed")
        #endif
    }
    
    /// Track token search
    public func trackTokenSearched(query: String) {
        Analytics.logEvent("token_searched", parameters: [
            "search_query": query,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        
        #if DEBUG
        print("📊 Analytics: token_searched - \(query)")
        #endif
    }
    
    /// Track when user selects a token
    public func trackTokenSelected(token: String, context: String = "swap") {
        Analytics.logEvent("token_selected", parameters: [
            "token": token,
            "context": context,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        
        #if DEBUG
        print("📊 Analytics: token_selected - \(token)")
        #endif
    }
    
    /// Track chart views
    public func trackChartViewed(token: String, timeframe: String = "1D") {
        Analytics.logEvent("chart_viewed", parameters: [
            "token": token,
            "timeframe": timeframe,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        
        #if DEBUG
        print("📊 Analytics: chart_viewed - \(token)")
        #endif
    }
    
    /// Track settings changes
    public func trackSettingsChanged(setting: String, value: String) {
        Analytics.logEvent("settings_changed", parameters: [
            "setting_name": setting,
            "new_value": value,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        
        #if DEBUG
        print("📊 Analytics: settings_changed - \(setting) = \(value)")
        #endif
    }
    
    /// Track transaction history viewed
    public func trackTransactionHistoryViewed() {
        Analytics.logEvent("transaction_history_viewed", parameters: [
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        
        #if DEBUG
        print("📊 Analytics: transaction_history_viewed")
        #endif
    }
    
    // MARK: - Error Events
    
    /// Track general errors
    public func trackError(
        errorType: String,
        errorMessage: String,
        context: String? = nil
    ) {
        var parameters: [String: Any] = [
            "error_type": errorType,
            "error_message": errorMessage,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let context = context {
            parameters["context"] = context
        }
        
        Analytics.logEvent("error_occurred", parameters: parameters)
        
        #if DEBUG
        print("📊 Analytics: error_occurred - \(errorType): \(errorMessage)")
        #endif
    }
    
    /// Track network errors
    public func trackNetworkError(
        network: String,
        errorMessage: String
    ) {
        Analytics.logEvent("network_error", parameters: [
            "network": network,
            "error_message": errorMessage,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        
        #if DEBUG
        print("📊 Analytics: network_error - \(network)")
        #endif
    }
}
