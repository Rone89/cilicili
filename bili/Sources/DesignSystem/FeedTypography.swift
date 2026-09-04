import SwiftUI
import UIKit

enum AppTypographyMode: Equatable {
    case legacy
    case nativeRefined
}

private struct AppTypographyModeKey: EnvironmentKey {
    static let defaultValue: AppTypographyMode = .legacy
}

extension EnvironmentValues {
    var appTypographyMode: AppTypographyMode {
        get { self[AppTypographyModeKey.self] }
        set { self[AppTypographyModeKey.self] = newValue }
    }
}

enum AppManualFontSize: Int, CaseIterable, Identifiable {
    case extraSmall
    case small
    case medium
    case standard
    case large
    case extraLarge
    case extraExtraLarge
    case accessibility

    static let defaultValue: AppManualFontSize = .standard

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .extraSmall: return "最小"
        case .small: return "较小"
        case .medium: return "小"
        case .standard: return "标准"
        case .large: return "大"
        case .extraLarge: return "较大"
        case .extraExtraLarge: return "特大"
        case .accessibility: return "辅助大字"
        }
    }

    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .extraSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .standard: return .large
        case .large: return .extraLarge
        case .extraLarge: return .extraExtraLarge
        case .extraExtraLarge: return .extraExtraExtraLarge
        case .accessibility: return .accessibilityMedium
        }
    }
}

enum AppTypography {
    enum Role: String, Hashable {
        case pageTitle
        case navigationTitle
        case sectionTitle
        case videoDetailTitle
        case feedVideoTitle
        case compactVideoTitle
        case dynamicBody
        case author
        case compactAuthor
        case commentAuthor
        case commentBody
        case metadata
        case tertiaryMetadata
        case action
        case badge
        case liveRoomTitle
        case liveChatName
        case liveChatBody
        case messageName
        case messagePreview
        case messageBody
        case settingsRow
        case settingsSubtitle
        case diagnostic

        var pointSize: CGFloat {
            switch self {
            case .pageTitle:
                return 34
            case .navigationTitle, .sectionTitle, .videoDetailTitle, .messageBody:
                return 17
            case .liveRoomTitle, .messageName, .settingsRow:
                return 16
            case .feedVideoTitle, .dynamicBody, .author, .commentBody:
                return 15
            case .compactVideoTitle, .commentAuthor, .liveChatBody, .messagePreview:
                return 14
            case .liveChatName, .settingsSubtitle:
                return 13
            case .compactAuthor, .metadata, .action, .diagnostic:
                return 12
            case .tertiaryMetadata, .badge:
                return 11
            }
        }

        var weight: Weight {
            switch self {
            case .pageTitle:
                return .bold
            case .navigationTitle, .sectionTitle, .badge:
                return .semibold
            case .author, .compactAuthor, .commentAuthor, .action, .liveRoomTitle, .liveChatName, .messageName:
                return .medium
            case .videoDetailTitle, .feedVideoTitle, .compactVideoTitle, .dynamicBody,
                 .commentBody, .metadata, .tertiaryMetadata, .liveChatBody,
                 .messagePreview, .messageBody, .settingsRow, .settingsSubtitle, .diagnostic:
                return .regular
            }
        }

        var relativeTextStyle: Font.TextStyle {
            switch self {
            case .pageTitle:
                return .largeTitle
            case .navigationTitle, .sectionTitle, .videoDetailTitle, .feedVideoTitle, .liveRoomTitle:
                return .headline
            case .compactVideoTitle, .author, .commentAuthor, .liveChatBody, .messagePreview:
                return .subheadline
            case .dynamicBody, .commentBody, .messageName, .messageBody, .settingsRow:
                return .body
            case .compactAuthor, .liveChatName, .metadata, .action, .diagnostic:
                return .caption
            case .tertiaryMetadata, .badge:
                return .caption2
            case .settingsSubtitle:
                return .footnote
            }
        }

        var uiTextStyle: UIFont.TextStyle {
            switch self {
            case .pageTitle:
                return .largeTitle
            case .navigationTitle, .sectionTitle, .videoDetailTitle, .feedVideoTitle, .liveRoomTitle:
                return .headline
            case .compactVideoTitle, .author, .commentAuthor, .liveChatBody, .messagePreview:
                return .subheadline
            case .dynamicBody, .commentBody, .messageName, .messageBody, .settingsRow:
                return .body
            case .compactAuthor, .liveChatName, .metadata, .action, .diagnostic:
                return .caption1
            case .tertiaryMetadata, .badge:
                return .caption2
            case .settingsSubtitle:
                return .footnote
            }
        }

        var design: Design {
            self == .diagnostic ? .monospaced : .default
        }

        var nativeTextStyle: Font.TextStyle {
            switch self {
            case .pageTitle:
                return .largeTitle
            case .videoDetailTitle:
                return .title3
            case .navigationTitle, .sectionTitle, .feedVideoTitle, .liveRoomTitle, .messageName:
                return .headline
            case .compactVideoTitle, .commentAuthor, .liveChatBody, .messagePreview:
                return .subheadline
            case .dynamicBody, .commentBody, .messageBody, .settingsRow:
                return .body
            case .author:
                return .subheadline
            case .compactAuthor, .liveChatName:
                return .footnote
            case .metadata, .settingsSubtitle:
                return .footnote
            case .action:
                return .subheadline
            case .tertiaryMetadata:
                return .caption
            case .badge:
                return .caption2
            case .diagnostic:
                return .caption
            }
        }

        var nativeUITextStyle: UIFont.TextStyle {
            switch self {
            case .pageTitle:
                return .largeTitle
            case .videoDetailTitle:
                return .title3
            case .navigationTitle, .sectionTitle, .feedVideoTitle, .liveRoomTitle, .messageName:
                return .headline
            case .compactVideoTitle, .commentAuthor, .liveChatBody, .messagePreview:
                return .subheadline
            case .dynamicBody, .commentBody, .messageBody, .settingsRow:
                return .body
            case .author:
                return .subheadline
            case .compactAuthor, .liveChatName:
                return .footnote
            case .metadata, .settingsSubtitle:
                return .footnote
            case .action:
                return .subheadline
            case .tertiaryMetadata:
                return .caption1
            case .badge:
                return .caption2
            case .diagnostic:
                return .caption1
            }
        }

        var nativeWeight: Weight? {
            switch self {
            case .pageTitle:
                return .bold
            case .videoDetailTitle, .compactVideoTitle, .commentAuthor, .badge:
                return .semibold
            case .liveChatName:
                return .medium
            default:
                return nil
            }
        }

        func font(pointSize: CGFloat) -> Font {
            .system(size: pointSize, weight: weight.swiftUIWeight, design: design.swiftUIDesign)
        }

        func nativeFont() -> Font {
            if let nativeWeight {
                return .system(
                    nativeTextStyle,
                    design: design.swiftUIDesign,
                    weight: nativeWeight.swiftUIWeight
                )
            }
            return .system(nativeTextStyle, design: design.swiftUIDesign)
        }

        func uiFont(
            contentSizeCategory: UIContentSizeCategory,
            mode: AppTypographyMode = .legacy
        ) -> UIFont {
            guard mode == .nativeRefined else {
                return legacyUIFont(contentSizeCategory: contentSizeCategory)
            }

            let traits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
            let preferredFont = UIFont.preferredFont(
                forTextStyle: nativeUITextStyle,
                compatibleWith: traits
            )
            let weightedFont = nativeWeight.map {
                UIFont.systemFont(ofSize: preferredFont.pointSize, weight: $0.uiKitWeight)
            } ?? preferredFont
            guard let design = design.uiKitDesign,
                  let descriptor = weightedFont.fontDescriptor.withDesign(design)
            else {
                return weightedFont
            }
            return UIFont(descriptor: descriptor, size: preferredFont.pointSize)
        }

        private func legacyUIFont(contentSizeCategory: UIContentSizeCategory) -> UIFont {
            let baseFont = AppTypography.baseUIFont(for: self)
            let traits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
            return UIFontMetrics(forTextStyle: uiTextStyle).scaledFont(
                for: baseFont,
                compatibleWith: traits
            )
        }
    }

    enum Weight: Equatable {
        case regular
        case medium
        case semibold
        case bold

        var swiftUIWeight: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }

        var uiKitWeight: UIFont.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }
    }

    enum Design {
        case `default`
        case monospaced

        var swiftUIDesign: Font.Design {
            switch self {
            case .default: return .default
            case .monospaced: return .monospaced
            }
        }

        var uiKitDesign: UIFontDescriptor.SystemDesign? {
            switch self {
            case .default: return nil
            case .monospaced: return .monospaced
            }
        }
    }

    private static func baseUIFont(for role: Role) -> UIFont {
        let font = UIFont.systemFont(ofSize: role.pointSize, weight: role.weight.uiKitWeight)
        guard let design = role.design.uiKitDesign,
              let descriptor = font.fontDescriptor.withDesign(design)
        else {
            return font
        }
        return UIFont(descriptor: descriptor, size: role.pointSize)
    }
}

private struct AppTypographyModifier: ViewModifier {
    @ScaledMetric private var scaledPointSize: CGFloat

    let role: AppTypography.Role
    @Environment(\.appTypographyMode) private var typographyMode

    init(role: AppTypography.Role) {
        self.role = role
        _scaledPointSize = ScaledMetric(
            wrappedValue: role.pointSize,
            relativeTo: role.relativeTextStyle
        )
    }

    func body(content: Content) -> some View {
        switch typographyMode {
        case .legacy:
            content.font(role.font(pointSize: scaledPointSize))
        case .nativeRefined:
            content.font(role.nativeFont())
        }
    }
}

private struct AppTypographyLegacyFallbackModifier: ViewModifier {
    @Environment(\.appTypographyMode) private var typographyMode

    let role: AppTypography.Role
    let legacyFont: Font

    func body(content: Content) -> some View {
        switch typographyMode {
        case .legacy:
            content.font(legacyFont)
        case .nativeRefined:
            content.font(role.nativeFont())
        }
    }
}

extension View {
    func appTypography(_ role: AppTypography.Role, fallback _: Font) -> some View {
        modifier(AppTypographyModifier(role: role))
    }

    func appTypography(_ role: AppTypography.Role) -> some View {
        modifier(AppTypographyModifier(role: role))
    }

    func appTypography(_ role: AppTypography.Role, legacyFont: Font) -> some View {
        modifier(
            AppTypographyLegacyFallbackModifier(
                role: role,
                legacyFont: legacyFont
            )
        )
    }
}

extension DynamicTypeSize {
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        default: return .large
        }
    }
}

enum FeedTypography {
    static let primaryTextSize: CGFloat = 15
    static let bodyLineSpacing: CGFloat = 2

    static let bodyFont: Font = .system(size: primaryTextSize, weight: .regular)
    static let titleFont: Font = .system(size: primaryTextSize, weight: .semibold)

    static let bodyUIFont = UIFont.systemFont(ofSize: primaryTextSize, weight: .regular)
    static let titleUIFont = UIFont.systemFont(ofSize: primaryTextSize, weight: .semibold)
}
