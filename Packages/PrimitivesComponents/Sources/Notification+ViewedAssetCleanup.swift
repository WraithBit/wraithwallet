// Notification+ViewedAssetCleanup.swift
// Copyright (c). Gem Wallet.

import Foundation

public extension Notification.Name {
    /// Posted by AssetScene when it disappears, passing the viewed `Asset` in `object`.
    static let viewedAssetNeedsCleanup = Notification.Name("viewedAssetNeedsCleanup")
}
