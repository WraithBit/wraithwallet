import SwiftUI

@MainActor
public extension View {
    func attachSwapBindings(_ viewModel: SwapSceneViewModel) -> some View {
        self
            .onAppear { viewModel.fetch() }
            .onChange(of: viewModel.amountInputModel.text, viewModel.onChangeFromValue)
            .onChange(of: viewModel.pairSelectorModel, viewModel.onChangePair)
            .onChange(of: viewModel.selectedSwapQuote, viewModel.onChangeSwapQuoute)
            .debounce(
                value: viewModel.swapState.fetch,
                interval: viewModel.swapState.fetch.delay,
                action: viewModel.onFetchStateChange
            )
            .debounce(
                value: viewModel.assetIds,
                initial: true,
                interval: .none,
                action: viewModel.onAssetIdsChange
            )
            .onChangeObserveQuery(
                request: Binding(
                    get: { viewModel.fromAssetRequest },
                    set: { viewModel.fromAssetRequest = $0 }
                ),
                value: Binding(
                    get: { viewModel.fromAsset },
                    set: { viewModel.fromAsset = $0 }
                ),
                action: viewModel.onChangeFromAsset
            )
            .onChangeObserveQuery(
                request: Binding(
                    get: { viewModel.toAssetRequest },
                    set: { viewModel.toAssetRequest = $0 }
                ),
                value: Binding(
                    get: { viewModel.toAsset },
                    set: { viewModel.toAsset = $0 }
                ),
                action: viewModel.onChangeToAsset
            )
    }
}
