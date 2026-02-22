// Copyright (c). Gem Wallet. All rights reserved.

import SwiftUI
import Components
import Style
import PrimitivesComponents
import UIKit

public struct SwapScene: View {
    public enum Presentation: Equatable {
        /// Original behaviour: List + safe-area bottom action
        case standalone
        /// Embed inside an outer ScrollView: no inner scrolling, but keeps the same visual styling
        case embedded
    }

    @FocusState private var focusedField: Bool
    @State private var model: SwapSceneViewModel

    private let presentation: Presentation

    // Update quote every 30 seconds, needed if you come back from the background.
    private let updateQuoteTimer = Timer.publish(every: 30, tolerance: 1, on: .main, in: .common).autoconnect()

    public init(model: SwapSceneViewModel, presentation: Presentation = .standalone) {
        _model = State(initialValue: model)
        self.presentation = presentation
    }

    public var body: some View {
        Group {
            switch presentation {
            case .standalone:
                standaloneBody
            case .embedded:
                embeddedBody
            }
        }
        .navigationTitle(model.title)
        .onChangeObserveQuery(
            request: $model.fromAssetRequest,
            value: $model.fromAsset,
            action: model.onChangeFromAsset
        )
        .onChangeObserveQuery(
            request: $model.toAssetRequest,
            value: $model.toAsset,
            action: model.onChangeToAsset
        )
        .debounce(
            value: model.swapState.fetch,
            interval: model.swapState.fetch.delay,
            action: model.onFetchStateChange
        )
        .debounce(
            value: model.assetIds,
            initial: true,
            interval: .none,
            action: model.onAssetIdsChange
        )
        .onChange(of: model.amountInputModel.text, model.onChangeFromValue)
        .onChange(of: model.pairSelectorModel, model.onChangePair)
        .onChange(of: model.selectedSwapQuote, model.onChangeSwapQuoute)
        .onReceive(updateQuoteTimer) { _ in
            model.fetch()
        }
        .onAppear {
            focusedField = true
        }
    }
}

// MARK: - Standalone (original List version)

private extension SwapScene {
    var standaloneBody: some View {
        List {
            swapFromSectionList
            swapToSectionList

            if model.shouldShowAdditionalInfo {
                additionalInfoSectionList
            }

            if let error = model.swapState.error {
                ListItemErrorView(errorTitle: model.errorTitle, error: error, infoAction: model.errorInfoAction)
            }
        }
        .listSectionSpacing(.compact)
        .safeAreaView {
            bottomActionViewStandalone
                .confirmationDialog(
                    model.swapDetailsViewModel?.highImpactWarningTitle ?? "",
                    presenting: $model.isPresentingPriceImpactConfirmation,
                    sensoryFeedback: .warning,
                    actions: { _ in
                        Button(
                            model.buttonViewModel.title,
                            role: .destructive,
                            action: model.onSelectSwapConfirmation
                        )
                    },
                    message: {
                        Text(model.isPresentingPriceImpactConfirmation ?? "")
                    }
                )
        }
    }

    var swapFromSectionList: some View {
        Section {
            SwapTokenView(
                model: model.swapTokenModel(type: .pay),
                text: $model.amountInputModel.text,
                onBalanceAction: model.onSelectFromMaxBalance,
                onSelectAssetAction: model.onSelectAssetPay
            )
            .buttonStyle(.borderless)
            .focused($focusedField)
        } header: {
            Text(model.swapFromTitle)
                .listRowInsets(.horizontalMediumInsets)
        } footer: {
            SwapChangeView(
                fromId: $model.pairSelectorModel.fromAssetId,
                toId: $model.pairSelectorModel.toAssetId
            )
            .padding(.top, .small)
            .frame(maxWidth: .infinity)
            .disabled(model.isSwitchAssetButtonDisabled)
            .textCase(nil)
            .listRowSeparator(.hidden)
            .listRowInsets(.horizontalMediumInsets)
        }
    }

    var swapToSectionList: some View {
        Section {
            SwapTokenView(
                model: model.swapTokenModel(type: .receive(chains: [], assetIds: [])),
                text: $model.toValue,
                showLoading: model.isLoading,
                disabledTextField: true,
                onBalanceAction: {},
                onSelectAssetAction: model.onSelectAssetReceive
            )
            .buttonStyle(.borderless)
        } header: {
            Text(model.swapToTitle)
                .listRowInsets(.horizontalMediumInsets)
        }
    }

    var additionalInfoSectionList: some View {
        Section {
            if let swapDetailsViewModel = model.swapDetailsViewModel {
                NavigationCustomLink(
                    with: SwapDetailsListView(model: swapDetailsViewModel),
                    action: model.onSelectSwapDetails
                )
            }
        }
    }
}

// MARK: - Embedded (VStack, but styled like the List cards)

private extension SwapScene {
    var embeddedBody: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                embeddedHeader(model.swapFromTitle)
                SwapTokenView(
                    model: model.swapTokenModel(type: .pay),
                    text: $model.amountInputModel.text,
                    onBalanceAction: model.onSelectFromMaxBalance,
                    onSelectAssetAction: model.onSelectAssetPay
                )
                .focused($focusedField)
            }
            .embeddedCard()

            SwapChangeView(
                fromId: $model.pairSelectorModel.fromAssetId,
                toId: $model.pairSelectorModel.toAssetId
            )
            .disabled(model.isSwitchAssetButtonDisabled)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 10) {
                embeddedHeader(model.swapToTitle)
                SwapTokenView(
                    model: model.swapTokenModel(type: .receive(chains: [], assetIds: [])),
                    text: $model.toValue,
                    showLoading: model.isLoading,
                    disabledTextField: true,
                    onBalanceAction: {},
                    onSelectAssetAction: model.onSelectAssetReceive
                )
            }
            .embeddedCard()

            if model.shouldShowAdditionalInfo, let swapDetailsViewModel = model.swapDetailsViewModel {
                Button(action: model.onSelectSwapDetails) {
                    SwapDetailsListView(model: swapDetailsViewModel)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .embeddedCard()
            }

            if let error = model.swapState.error {
                ListItemErrorView(errorTitle: model.errorTitle, error: error, infoAction: model.errorInfoAction)
                    .embeddedCard()
            }

            bottomActionViewEmbedded
                .confirmationDialog(
                    model.swapDetailsViewModel?.highImpactWarningTitle ?? "",
                    presenting: $model.isPresentingPriceImpactConfirmation,
                    sensoryFeedback: .warning,
                    actions: { _ in
                        Button(
                            model.buttonViewModel.title,
                            role: .destructive,
                            action: model.onSelectSwapConfirmation
                        )
                    },
                    message: {
                        Text(model.isPresentingPriceImpactConfirmation ?? "")
                    }
                )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    func embeddedHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}

// MARK: - Bottom action views

private extension SwapScene {
    var buttonView: some View {
        StateButton(
            text: model.buttonViewModel.title,
            type: model.buttonViewModel.type,
            image: model.buttonViewModel.icon,
            infoTitle: model.buttonViewModel.infoText,
            action: onSelectActionButton
        )
        .frame(maxWidth: Spacing.scene.button.maxWidth)
    }

    @ViewBuilder
    var bottomActionViewStandalone: some View {
        VStack(spacing: 0) {
            Divider()
                .frame(height: 1 / UIScreen.main.scale)
                .background(Colors.grayVeryLight)
                .isVisible(focusedField)

            Group {
                if model.buttonViewModel.isVisible {
                    buttonView
                } else if focusedField {
                    PercentageAccessoryView(
                        percents: SwapSceneViewModel.inputPercents,
                        onSelectPercent: {
                            focusedField = false
                            model.onSelectPercent($0)
                        },
                        onDone: {
                            focusedField = false
                        }
                    )
                }
            }
            .padding(.small)
        }
        .background(Colors.grayBackground)
    }

    @ViewBuilder
    var bottomActionViewEmbedded: some View {
        VStack(spacing: 10) {
            if model.buttonViewModel.isVisible {
                StateButton(
                    text: model.buttonViewModel.title,
                    type: model.buttonViewModel.type,
                    image: model.buttonViewModel.icon,
                    infoTitle: model.buttonViewModel.infoText,
                    action: onSelectActionButton
                )
                // Full-size like the standalone footer button
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 4)
            } else if focusedField {
                PercentageAccessoryView(
                    percents: SwapSceneViewModel.inputPercents,
                    onSelectPercent: {
                        focusedField = false
                        model.onSelectPercent($0)
                    },
                    onDone: {
                        focusedField = false
                    }
                )
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

// MARK: - Actions

private extension SwapScene {
    func onSelectActionButton() {
        focusedField = false
        model.buttonViewModel.action()
    }
}

// MARK: - Embedded styling helpers

private extension View {
    func embeddedCard() -> some View {
        self
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
    }
}
