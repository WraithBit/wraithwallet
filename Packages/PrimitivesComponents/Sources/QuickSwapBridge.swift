import Foundation
import Primitives

/// Bridge to coordinate Quick-Swap and temporary asset adds.
/// - Publishes a prefilled asset for the Swap sheet.
/// - Tracks which assets were *newly added* so we can auto-hide later.
/// - Tracks which assets were already in the wallet so we never hide those.
public final class QuickSwapBridge: ObservableObject {
    /// When set, MainTabView will open the Swap sheet prefilled with this asset.
    @Published public var prefilledAsset: Asset?

    /// Assets we **added on-the-fly** (first time) for viewing/swap.
    public var temporarilyAddedAssets = Set<AssetId>()

    /// Assets the user **already had** in their wallet when they tapped.
    public var prefilledKnownAssets = Set<AssetId>()

    public init() {}

    // MARK: - Temporary markers

    public func markTemporarilyAdded(_ id: AssetId) {
        temporarilyAddedAssets.insert(id)
    }

    public func clearTemporaryMark(_ id: AssetId) {
        temporarilyAddedAssets.remove(id)
    }

    public func clearAllTemporaryMarks() {
        temporarilyAddedAssets.removeAll()
    }

    // MARK: - Known markers

    public func markWasInWallet(_ id: AssetId) {
        prefilledKnownAssets.insert(id)
    }

    public func clearWasInWallet(_ id: AssetId) {
        prefilledKnownAssets.remove(id)
    }

    public func clearAllKnownMarks() {
        prefilledKnownAssets.removeAll()
    }
}
