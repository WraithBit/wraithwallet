// Copyright (c). Gem Wallet. All rights reserved.

import SwiftUI

public extension View {
    /// Adds content pinned to a safe-area edge (bottom by default), matching the old `safeAreaBar` usage.
    @ViewBuilder
    func safeAreaView<Content: View>(
        edge: VerticalEdge = .bottom,
        @ViewBuilder content: () -> Content
    ) -> some View {
        // Use safeAreaInset universally; it works iOS 15+
        safeAreaInset(edge: edge) {
            content()
        }
    }
}
