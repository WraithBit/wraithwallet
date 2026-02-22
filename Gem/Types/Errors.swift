// Copyright (c). Gem Wallet. All rights reserved.

import Foundation
import Gemstone
import Localization
import Primitives

extension Gemstone.GatewayError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .NetworkError(let string):
            return string

        @unknown default:
            // Fallback for any new cases added in the Gemstone module
            return String(describing: self)
        }
    }
}

extension Gemstone.GemstoneError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .AnyError(let string):
            return string

        @unknown default:
            return String(describing: self)
        }
    }
}

extension Gemstone.SwapperError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .NotSupportedChain: return Localized.Errors.Swap.notSupportedChain
        case .NotSupportedAsset: return Localized.Errors.Swap.notSupportedAsset
        case .NoQuoteAvailable: return Localized.Errors.Swap.noQuoteAvailable
        case .NotSupportedPair, .NoAvailableProvider: return Localized.Errors.Swap.notSupportedPair
        case .InputAmountTooSmall: return Localized.Errors.Swap.amountTooSmall

        case .InvalidAddress(let error),
             .InvalidAmount(let error),
             .NetworkError(let error),
             .AbiError(let error),
             .ComputeQuoteError(let error),
             .TransactionError(let error):
            return error

        case .InvalidRoute:
            return "Invalid route"

        case .NotImplemented:
            return AnyError.notImplemented.errorDescription

        @unknown default:
            return String(describing: self)
        }
    }
}

extension Gemstone.AlienError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .RequestError(msg: let msg): return msg
        case .ResponseError(msg: let msg): return msg
        case .Http(let status, _): return "Response status: \(status)"

        @unknown default:
            return String(describing: self)
        }
    }
}
