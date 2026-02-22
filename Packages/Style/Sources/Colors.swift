import SwiftUI

public struct Colors {
    // Base palette (restored to your original fork)
    public static let white = Color.dynamicColor("#FFFFFF", dark: "#222222")
    public static let whiteSolid = Color.dynamicColor("FFFFFF")
    public static let black = Color.dynamicColor("#222222", dark: "FFFFFF")

    // Your original "blue" was actually the brand green
    public static let blue = Color.dynamicColor("#0EC72E")
    public static let blueDark = Color.dynamicColor("#19A430")

    public static let red = Color.dynamicColor("#F84E4E")
    public static let redLight = Color.dynamicColor("#FFF1F1", dark: "#462D30")

    public static let green = Color.dynamicColor("#1B9A6C")
    public static let greenLight = Color.dynamicColor("EAFAF5", dark: "27423C")

    public static let orange = Color.dynamicColor("#FF9314")

    public static let gray = Color.dynamicColor("#818181")
    public static let grayLight = Color.dynamicColor("#969996")
    public static let grayVeryLight = Color.dynamicColor("#F4F4F4", dark: "#333333")

    // Restore dark backgrounds to #1A1A1C to match original fork
    public static let grayBackground = Color.dynamicColor("#F2F2F7", dark: "#1A1A1C")
    public static let grayDarkBackground = Color.dynamicColor("#E6E6F0", dark: "#1A1A1C")

    public static let secondaryText = Color.dynamicColor("#818181")

    // Alias to avoid “no member 'textSecondary'” errors elsewhere
    public static let textSecondary = Colors.secondaryText

    public static let listStyleColor = UIColor.dynamicColor(
        UIColor.systemBackground.color,
        dark: UIColor.secondarySystemBackground.color
    )

    public static let insetGroupedListStyle = UIColor.dynamicColor(
        UIColor.systemGroupedBackground.color,
        dark: UIColor.black.color
    )
}

// MARK: - Empty

extension Colors {
    public struct Empty {
        public static let imageBackground = Color(.quaternaryLabel)
        public static let image = Color.dynamicColor("#767A81")
        public static let buttonsBackground = Color(.quaternaryLabel)

        // Keep this from the new repo to avoid breaking callers
        public static let listEmpty = Color(.secondarySystemFill)
    }
}

// MARK: - Faded Variants (tuned to harmonise with restored brand green)

extension Colors {
    // Lightened tints of the brand green ("blue") for chips, badges, etc.
    public static let blueFaded = Color.dynamicColor("#5FEA84", dark: "#4ED475")
    public static let blueDarkFaded = Color.dynamicColor("#49D46D", dark: "#41C363")

    // Neutral fades unchanged (generic utilities)
    public static let whiteFaded = Color.dynamicColor("#F0F0F0", dark: "#444444")
    public static let grayFaded = Color.dynamicColor("#C0C0C0", dark: "#606060")
    public static let grayLightFaded = Color.dynamicColor("#CACBCA", dark: "#4D524D")
    public static let grayVeryLightFaded = Color.dynamicColor("#F9F9F9", dark: "#666666")
    public static let blackFaded = Color.dynamicColor("#919191", dark: "#7F7F7F")

    public static let redFaded = Color.dynamicColor("#FB7676", dark: "#FB7676")
    public static let redFadedLight = Color.dynamicColor("#FC8E8E", dark: "#FC8E8E")

    public static let greenFaded = Color.dynamicColor("#4EAC84", dark: "#4EAC84")
    public static let greenFadedLight = Color.dynamicColor("#67B593", dark: "#67B593")
}

#Preview {
    let colors: [(name: String, color: Color)] = [
        ("White", Colors.white),
        ("White solid", Colors.whiteSolid),
        ("Black", Colors.black),
        ("Blue", Colors.blue),
        ("Blue dark", Colors.blueDark),
        ("Red", Colors.red),
        ("Red light", Colors.redLight),
        ("Green", Colors.green),
        ("Green light", Colors.greenLight),
        ("Orange", Colors.orange),
        ("Gray", Colors.gray),
        ("Gray light", Colors.grayLight),
        ("Gray very light", Colors.grayVeryLight),
        ("Gray background", Colors.grayBackground),
        ("Gray dark background", Colors.grayDarkBackground),
        ("Secondary text", Colors.secondaryText),
        ("List style colour", Color(Colors.listStyleColor)),
        ("Inset grouped list style colour", Color(Colors.insetGroupedListStyle)),
    ]

    return List {
        ForEach(colors, id: \.name) { color in
            HStack {
                Text(color.name)
                    .multilineTextAlignment(.leading)
                    .frame(width: 174)

                RoundedRectangle(cornerRadius: 4)
                    .fill(color.color)
                    .padding(.extraSmall)
                    .colorScheme(.light)

                RoundedRectangle(cornerRadius: 4)
                    .fill(color.color)
                    .padding(.extraSmall)
                    .colorScheme(.dark)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0))
        }
    }
    .listStyle(InsetGroupedListStyle())
}
