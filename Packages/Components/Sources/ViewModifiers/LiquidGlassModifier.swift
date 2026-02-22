import SwiftUI

public struct LiquidGlassModifier: ViewModifier {
    private let tint: Color?
    private let interactive: Bool

    public init(tint: Color?, interactive: Bool) {
        self.tint = tint
        self.interactive = interactive
    }

    public func body(content: Content) -> some View {
        content
            // Base glassy material
            .background(.ultraThinMaterial)
            // Optional tint overlay to nudge the hue
            .overlay {
                if let tint {
                    Rectangle()
                        .fill(tint.opacity(interactive ? 0.18 : 0.10))
                        .allowsHitTesting(false)
                }
            }
            // Slight dim when not interactive, similar to “non-interactive glass”
            .opacity(interactive ? 1.0 : 0.95)
            .compositingGroup()
    }
}

public extension View {
    @ViewBuilder
    func liquidGlass<Fallback: View>(
        tint: Color? = nil,
        interactive: Bool = true,
        fallback: (Self) -> Fallback
    ) -> some View {
        // We no longer rely on iOS 18’s .glassEffect; this works on iOS 15+
        modifier(LiquidGlassModifier(tint: tint, interactive: interactive))
    }

    @ViewBuilder
    func liquidGlass(
        tint: Color? = nil,
        interactive: Bool = true
    ) -> some View {
        modifier(LiquidGlassModifier(tint: tint, interactive: interactive))
    }
}
