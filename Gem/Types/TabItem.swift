// Copyright (c). Gem Wallet. All rights reserved.

import Foundation

enum TabItem: Identifiable, CaseIterable, Sendable {
    case wallet
    case swap
    case collections
    case activity
    case settings
    case markets

    var id: Self { self }
}
