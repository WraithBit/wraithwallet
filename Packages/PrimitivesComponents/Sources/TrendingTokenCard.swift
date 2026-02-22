// Copyright (c). Gem Wallet. All rights reserved.

import SwiftUI
import Components
import Primitives
import Style

public struct TrendingTokenCard: View {
    let token: TrendingToken
    let rank: Int
    let onTap: (() -> Void)?
    
    init(token: TrendingToken, rank: Int, onTap: (() -> Void)? = nil) {
        self.token = token
        self.rank = rank
        self.onTap = onTap
    }
    
    public var body: some View {
        Button(action: {
            onTap?()
        }) {
            VStack(alignment: .leading, spacing: .small) {
                HStack {
                    Text("#\(rank)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Colors.gray)
                    
                    Spacer()
                    
                    AsyncImageView(
                        url: URL(string: token.image),
                        placeholder: {
                            Circle()
                                .fill(Colors.grayVeryLight)
                                .frame(width: 24, height: 24)
                        },
                        image: { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                        }
                    )
                }
                
                VStack(alignment: .leading, spacing: .extraSmall) {
                    Text(token.symbol.uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("$\(formattedPrice)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Colors.gray)
                        .lineLimit(1)
                }
                
                if let change = token.priceChangePercentage24h {
                    HStack(spacing: .extraSmall) {
                        Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                        
                        Text("\(abs(change), specifier: "%.1f")%")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(change >= 0 ? Colors.green : Colors.red)
                }
                
                // Mini sparkline
                if let sparkline = token.sparklineIn7d?.price, !sparkline.isEmpty {
                    MiniSparklineView(
                        data: sparkline,
                        isPositive: (token.priceChangePercentage24h ?? 0) >= 0
                    )
                    .frame(height: 20)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.medium)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Colors.grayBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Colors.grayVeryLight, lineWidth: 1)
                )
        )
        .frame(width: 120)
    }
    
    private var formattedPrice: String {
        if token.currentPrice >= 1 {
            return String(format: "%.2f", token.currentPrice)
        } else if token.currentPrice >= 0.01 {
            return String(format: "%.4f", token.currentPrice)
        } else {
            return String(format: "%.6f", token.currentPrice)
        }
    }
}

struct MiniSparklineView: View {
    let data: [Double]
    let isPositive: Bool
    
    var body: some View {
        GeometryReader { geometry in
            let path = createPath(in: geometry.size)
            
            Path(path)
                .stroke(
                    isPositive ? Colors.green : Colors.red,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
        }
    }
    
    private func createPath(in size: CGSize) -> CGPath {
        let path = UIBezierPath()
        
        guard !data.isEmpty, data.count > 1 else { return path.cgPath }
        
        let minY = data.min() ?? 0
        let maxY = data.max() ?? 0
        let range = maxY - minY
        
        guard range > 0 else {
            // If no range, draw a flat line
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            return path.cgPath
        }
        
        let stepX = size.width / CGFloat(data.count - 1)
        
        for (index, value) in data.enumerated() {
            let x = CGFloat(index) * stepX
            let y = size.height - ((value - minY) / range) * size.height
            
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path.cgPath
    }
}

// MARK: - AsyncImageView Helper
private struct AsyncImageView<Placeholder: View, ImageView: View>: View {
    let url: URL?
    let placeholder: () -> Placeholder
    let image: (Image) -> ImageView
    
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let loadedImage):
                image(loadedImage)
            case .failure(_), .empty:
                placeholder()
            @unknown default:
                placeholder()
            }
        }
    }
}
